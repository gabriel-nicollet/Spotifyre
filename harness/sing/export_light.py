# /// script
# requires-python = ">=3.11,<3.13"
# dependencies = [
#     "torch==2.7.1",
#     "transformers==4.55.4",
#     "coremltools==9.0",
#     "einops==0.8.1",
#     "safetensors",
#     "huggingface_hub",
#     "numpy<2.3",
# ]
# ///
"""Karaoke's light voice model: Mini-BS-RoFormer-18M's vocal stem exported for Core ML as a drop-in for
separator-ane.mlmodelc (SGSingSeparator.m's contract: `spectrum` [1, 2050, 201, 2] in, the layout
(2 * bin + channel, frame, re/im), and `vocals_spectrum` of the same shape out, the STFT around it done by the app).

    uv run harness/sing/export_light.py <out dir> [<audio for the check, any file afconvert reads>]

writes <out dir>/separator-light.mlpackage, compiles it to <out dir>/separator-light.mlmodelc (xcrun coremlcompiler)
and checks the Core ML model on the CPU against the PyTorch model in float32 on that audio's spectrum (or a
synthetic mix). Changes from the published model, none of which change its maths:
- only the vocals' mask estimator (stem 3) is kept, the others' 3.2 M parameters dropped;
- every RMSNorm divides its row by the row's largest value first, so float16 does not overflow on the raw
  spectrum (|X| reaches 1024): RMSNorm ignores scale, and eps is scaled with it;
- the register tokens are concatenated instead of written into a slice, and attention is written out (its K/V
  heads repeated for the 8 query heads), so the graph traces;
- the model is fed the app's STFT (hop 441, 201 frames for 2 s) rather than its own (hop 512), as the model tested
  on the phone on 2026-10-08 was.
"""
import json
import math
import os
import subprocess
import sys
import tempfile
import types
import wave

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from huggingface_hub import snapshot_download
from transformers import AutoModel

REPO = "HiDolen/Mini-BS-RoFormer-18M"
REVISION = "d3ff400db0c72c236775ecc82e038f3117e52bf8"
VOCALS = 3
FRAMES, BINS, FFT, HOP, SECONDS = 201, 1025, 2048, 441, 88200


class SafeRMSNorm(nn.Module):
    def __init__(self, norm: nn.RMSNorm):
        super().__init__()
        self.weight = norm.weight
        self.root_eps = math.sqrt(norm.eps)

    def forward(self, x):
        m = x.abs().amax(dim=-1, keepdim=True).clamp(min=self.root_eps)
        y = x / m
        # eps / m^2 written as (sqrt(eps) / m)^2: at most 1, so it cannot overflow either.
        return y * torch.rsqrt(y.pow(2).mean(dim=-1, keepdim=True) + (self.root_eps / m).pow(2)) * self.weight


def safe_norms(module: nn.Module):
    for name, child in module.named_children():
        if isinstance(child, nn.RMSNorm):
            setattr(module, name, SafeRMSNorm(child))
        else:
            safe_norms(child)


def attention_forward(self, hidden_states, position_embeddings, attention_mask=None):
    b, s, _ = hidden_states.shape
    heads, kv, d = self.config.num_attention_heads, self.config.num_key_value_heads, self.head_dim
    q = self.q_proj(hidden_states).view(b, s, heads, d).transpose(1, 2)
    k = self.k_proj(hidden_states).view(b, s, kv, d).transpose(1, 2)
    v = self.v_proj(hidden_states).view(b, s, kv, d).transpose(1, 2)
    cos, sin = position_embeddings
    cos, sin = cos.unsqueeze(1), sin.unsqueeze(1)

    def rotate(x):
        return torch.cat((-x[..., d // 2:], x[..., : d // 2]), dim=-1)

    q, k = q * cos + rotate(q) * sin, k * cos + rotate(k) * sin
    k = k.repeat_interleave(heads // kv, dim=1)
    v = v.repeat_interleave(heads // kv, dim=1)
    weights = torch.softmax(torch.matmul(q, k.transpose(-1, -2)) * self.scaling, dim=-1)
    out = torch.matmul(weights, v).transpose(1, 2).reshape(b, s, heads * d)
    return self.o_proj(out), None


class Core(nn.Module):
    """BSRoformerModel.forward with the register tokens concatenated and the rotary tables precomputed."""

    def __init__(self, model):
        super().__init__()
        self.m = model
        rn = model.config.register_token_num
        n = len(model.config.freqs_per_bands)
        probe = torch.zeros(1, 1, 1, model.config.hidden_size)

        def table(length):
            cos, sin = model.rotary_emb(probe, torch.arange(length).unsqueeze(0))
            return F.pad(cos, (0, 0, 0, rn), value=1.0), F.pad(sin, (0, 0, 0, rn), value=0.0)

        self.register_buffer("tcos", table(FRAMES)[0]), self.register_buffer("tsin", table(FRAMES)[1])
        self.register_buffer("fcos", table(n)[0]), self.register_buffer("fsin", table(n)[1])

    def forward(self, x):
        m = self.m
        h = m.band_split(x)
        b, t, n, d = h.shape
        rn = m.config.register_token_num
        top = torch.cat([h, torch.zeros(b, t, rn, d, dtype=h.dtype)], dim=2)
        bottom = torch.cat([torch.zeros(b, rn, n, d, dtype=h.dtype), m.register_tokens.unsqueeze(0).expand(b, -1, -1, -1)], dim=2)
        h = torch.cat([top, bottom], dim=1)
        for time_transformer, freq_transformer in m.layers:
            h = time_transformer(h, position_embeddings=(self.tcos, self.tsin), attention_mask=None)
            h = freq_transformer(h, position_embeddings=(self.fcos, self.fsin), attention_mask=None)
        return m.final_norm(h[:, :t, :n, :])


class Separator(nn.Module):
    def __init__(self, full):
        super().__init__()
        self.core = Core(full.model)
        self.mask = full.mask_estimators[VOCALS]

    def forward(self, spectrum):
        # (2 * bin + channel, frame, re/im) -> (frame, (bin channel re/im)), the model's "b t (f c T)".
        x = spectrum.permute(0, 2, 1, 3).reshape(1, FRAMES, 4 * BINS)
        mask = self.mask(self.core(x)).reshape(1, FRAMES, 2 * BINS, 2).permute(0, 2, 1, 3)
        sr, si, mr, mi = spectrum[..., 0], spectrum[..., 1], mask[..., 0], mask[..., 1]
        return torch.stack([sr * mr - si * mi, sr * mi + si * mr], dim=-1)


def reference(full, spectrum):
    """The published model's own path: its forward from the merged spectrum on, vocals only, float32."""
    x = spectrum.permute(0, 2, 1, 3).reshape(1, FRAMES, 4 * BINS)
    mask = full.mask_estimators[VOCALS](full.model(x)).reshape(1, FRAMES, 2 * BINS, 2).permute(0, 2, 1, 3)
    return torch.view_as_real(torch.view_as_complex(spectrum.contiguous()) * torch.view_as_complex(mask.contiguous()))


def spectrum_of(audio):
    """The app's STFT: torch's periodic Hann, unnormalised, centered, (2 * bin + channel, frame, re/im)."""
    s = torch.stft(audio, FFT, HOP, FFT, window=torch.hann_window(FFT), center=True, return_complex=True)  # [2, 1025, 201]
    s = torch.view_as_real(s).permute(1, 0, 2, 3).reshape(1, 2 * BINS, FRAMES, 2)
    return s.contiguous()


def test_audio(path):
    if path:
        with tempfile.TemporaryDirectory() as tmp:
            raw = os.path.join(tmp, "a.wav")
            subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@44100", "-c", "2", path, raw], check=True)
            with wave.open(raw) as file:
                data = np.frombuffer(file.readframes(file.getnframes()), dtype="<i2").astype(np.float32) / 32768
        frames = data.reshape(-1, 2)
        start = max(0, (len(frames) - SECONDS) // 2)   # two seconds from the middle
        frames = np.pad(frames[start:start + SECONDS], ((0, max(0, SECONDS - len(frames) + start)), (0, 0)))
        return torch.from_numpy(frames.T.copy())
    t = torch.arange(SECONDS) / 44100
    rng = torch.Generator().manual_seed(1)
    chords = sum(0.15 * torch.sin(2 * math.pi * f * t) for f in (110, 220, 277.2, 329.6))
    voice = 0.3 * torch.sin(2 * math.pi * 440 * t + 3 * torch.sin(2 * math.pi * 5 * t)) * (torch.sin(2 * math.pi * 0.7 * t) > 0)
    noise = 0.02 * torch.randn(2, SECONDS, generator=rng)
    return torch.stack([chords + voice, chords + 0.8 * voice]) + noise


def main():
    out = os.path.abspath(sys.argv[1])
    os.makedirs(out, exist_ok=True)
    folder = snapshot_download(REPO, revision=REVISION, allow_patterns=["*.json", "*.py", "model.safetensors"])
    full = AutoModel.from_pretrained(folder, trust_remote_code=True, torch_dtype=torch.float32).eval()
    spectrum = spectrum_of(test_audio(sys.argv[2] if len(sys.argv) > 2 else None))
    with torch.no_grad():
        expected = reference(full, spectrum)
        for module in full.modules():
            if type(module).__name__ == "BSRoformerAttention":
                module.forward = types.MethodType(attention_forward, module)
        safe_norms(full)
        separator = Separator(full).eval()
        rewritten = separator(spectrum)
    print(f"rewrite vs published (float32): {snr(expected, rewritten):.1f} dB")

    traced = torch.jit.trace(separator, spectrum)
    package = ct.convert(
        traced,
        inputs=[ct.TensorType(name="spectrum", shape=(1, 2 * BINS, FRAMES, 2), dtype=np.float32)],
        outputs=[ct.TensorType(name="vocals_spectrum", dtype=np.float16)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS18,
    )
    package.short_description = "Karaoke's light voice model: Mini-BS-RoFormer-18M's vocals (HiDolen, MIT), exported by Vitrine"
    path = os.path.join(out, "separator-light.mlpackage")
    package.save(path)
    subprocess.run(["xcrun", "coremlcompiler", "compile", path, out], check=True)

    cpu = ct.models.MLModel(path, compute_units=ct.ComputeUnit.CPU_ONLY)
    got = torch.from_numpy(cpu.predict({"spectrum": spectrum.numpy()})["vocals_spectrum"].astype(np.float32))
    print(f"Core ML float16 on the CPU vs published (float32): {snr(expected, got):.1f} dB")
    print(json.dumps({"vocals_energy_ratio": float(expected.pow(2).sum() / spectrum.pow(2).sum())}))


def snr(reference, test):
    return 10 * math.log10(float(reference.pow(2).sum()) / max(float((reference - test).pow(2).sum()), 1e-30))


if __name__ == "__main__":
    main()
