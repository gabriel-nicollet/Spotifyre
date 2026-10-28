#!/usr/bin/env python3
"""Fit observed clock offsets. This does not establish sample-accurate recording alignment."""
import argparse
import math
import re
import statistics
import sys
from dataclasses import dataclass, field
from pathlib import Path

PREFIX = "lossless-anchor:"
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
FIELDS = re.compile(r"([a-z_]+)=([^\s]+)")
CLOCKS = ("position_ms", "raw_ms", "karaoke_ms")


def parse(lines):
    for number, line in enumerate(lines, 1):
        line = ANSI.sub("", line)
        if PREFIX not in line:
            continue
        row = dict(FIELDS.findall(line.split(PREFIX, 1)[1]))
        try:
            for name in ("session", "seq", "kind", "uri", "epoch", "sample_epoch", "output"):
                if name not in row:
                    raise ValueError(f"missing {name}")
            for name in ("control_host", "host", "source_frame", "rate", "age_ms", "speed",
                         "read_ms", "sample", "silent", "status", "playing", "paused", "dropped", *CLOCKS):
                row[name] = float(row[name])
                if not math.isfinite(row[name]):
                    raise ValueError(f"nonfinite {name}")
            if row.get("v") != "1":
                raise ValueError("unsupported version")
        except (KeyError, ValueError) as error:
            raise ValueError(f"line {number}: {error}") from error
        yield row


@dataclass
class Occurrence:
    session: str
    reason: str
    uri: str
    start: float
    rows: list = field(default_factory=list)
    rejected: int = 0


def occurrences(rows, settle=1.0, max_age=250.0):
    groups = []
    previous = None
    seen = set()
    for row in rows:
        identity = (row["session"], row["seq"])
        if identity in seen:
            continue  # Some syslog captures carry the same SGLog line twice.
        seen.add(identity)
        reason = None
        if previous is None or row["session"] != previous["session"]:
            reason = row["kind"] if row["kind"] != "sample" else "capture_start"
        elif row["control_host"] < previous["control_host"]:
            raise ValueError("control timestamps went backwards within a session")
        elif row["kind"] != "sample":
            reason = row["kind"]
        else:
            for key in ("uri", "epoch", "output", "rate", "speed", "dropped"):
                if row[key] != previous[key]:
                    reason = key
                    break
        if reason:
            groups.append(Occurrence(row["session"], reason, row["uri"], row["control_host"]))
        group = groups[-1]
        valid = (row["kind"] == "sample" and row["sample"] == 1 and row["silent"] == 0
                 and row["status"] == 0 and row["playing"] == 1 and row["paused"] == 0
                 and row["sample_epoch"] == row["epoch"] and row["rate"] > 0 and row["speed"] > 0
                 and 0 <= row["age_ms"] <= max_age and 0 <= row["read_ms"] <= 20
                 and row["control_host"] - group.start >= settle and row["uri"] != "-")
        if valid and group.rows and row["host"] <= group.rows[-1]["host"]:
            valid = False
        if valid:
            group.rows.append(row)
        else:
            group.rejected += 1
        previous = row
    return groups


def fit(group, clock):
    pairs = []
    for row in group.rows:
        if row[clock] < 0:
            continue
        # Karaoke names a bare track id, whereas the observer exposes a full URI.
        if clock == "karaoke_ms" and row.get("karaoke_uri", "-") not in (row["uri"], row["uri"].rsplit(":", 1)[-1]):
            continue
        x = row["source_frame"] / row["rate"]
        # Project the control read back to the start of the native pull. Read-ahead bursts,
        # Core Audio's block timing and public clock corrections remain measurement error.
        y = row[clock] / 1000 - (row["control_host"] - row["host"]) * row["speed"]
        pairs.append((x, y - x))
    if len(pairs) < 3:
        return None
    xs, offsets = zip(*pairs)
    span = max(xs) - min(xs)
    if span <= 0:
        return None
    mean_x, a = statistics.mean(xs), statistics.mean(offsets)
    denominator = sum((x - mean_x) ** 2 for x in xs)
    slope = sum((x - mean_x) * (offset - a) for x, offset in pairs) / denominator
    rms = math.sqrt(statistics.mean((offset - a) ** 2 for offset in offsets)) * 1000
    detrended = math.sqrt(statistics.mean((offset - a - slope * (x - mean_x)) ** 2 for x, offset in pairs)) * 1000
    return dict(n=len(pairs), a_ms=a * 1000, jitter_ms=rms, detrended_ms=detrended,
                drift_ppm=slope * 1e6, span_s=span)


def report(groups, out=sys.stdout):
    last = {clock: None for clock in CLOCKS}
    pending = {clock: [] for clock in CLOCKS}
    for number, group in enumerate(groups, 1):
        print(f"occurrence={number} session={group.session} event={group.reason} uri={group.uri} "
              f"accepted={len(group.rows)} rejected={group.rejected}", file=out)
        for clock in CLOCKS:
            pending[clock].append(group.reason)
            result = fit(group, clock)
            if result is None:
                print(f"  clock={clock} fit=insufficient", file=out)
                continue
            prior = last[clock]
            same_session = prior and prior[0] == group.session
            jump = f"{result['a_ms'] - prior[1]:.3f}" if same_session else "unknown"
            kinds = "+".join(pending[clock]) if same_session else "baseline"
            print(f"  clock={clock} n={result['n']} span_s={result['span_s']:.3f} "
                  f"a_ms={result['a_ms']:.3f} jitter_ms={result['jitter_ms']:.3f} "
                  f"detrended_ms={result['detrended_ms']:.3f} drift_ppm={result['drift_ppm']:.3f} "
                  f"jump_ms={jump} across={kinds}", file=out)
            last[clock] = (group.session, result["a_ms"])
            pending[clock] = []


def selftest():
    import io
    def line(seq, t, kind="sample", offset=2, drift=0, **changes):
        frame = t * 48000
        row = dict(v=1, session=1, seq=seq, kind=kind, uri="spotify:track:test", karaoke_uri="test",
                   epoch=1, sample_epoch=1, output=42, control_host=t + .05, host=t,
                   source_frame=frame, frames=480, rate=48000, age_ms=50, speed=1.5, read_ms=.1,
                   sample=1, silent=0, status=0, playing=1, paused=0, dropped=0)
        for clock in CLOCKS:
            row[clock] = (t + offset + t * drift + .05 * 1.5) * 1000
        row.update(changes)
        return "syslog [spotifyglass] " + PREFIX + " " + " ".join(f"{k}={v}" for k, v in row.items())
    lines = [line(1, 0, "start")]
    lines += [line(i + 1, i, drift=100e-6) for i in range(1, 11)]
    lines += [line(12, 11, "seek", epoch=2), line(13, 11.1, sample_epoch=1, epoch=2)]
    lines += [line(i + 3, i, offset=5, epoch=2, sample_epoch=2) for i in range(12, 22)]
    groups = occurrences(parse(lines))
    assert len(groups) == 2
    a, b = (fit(g, "raw_ms") for g in groups)
    assert abs(a["drift_ppm"] - 100) < 1e-6 and a["detrended_ms"] < 1e-6
    assert abs(b["a_ms"] - 5000) < 1e-6 and abs(b["drift_ppm"]) < 1e-6
    assert groups[1].rejected == 2
    stream = io.StringIO()
    report(groups, stream)
    assert "across=seek" in stream.getvalue() and "jump_ms=2999.450" in stream.getvalue()
    # Pauses and event clusters must survive even if they cannot themselves be fitted.
    events = ("pause", "resume", "skip", "track", "repeat", "sing_on", "sing_off", "route", "speed_pitch")
    rows = list(parse([line(i, i, kind) for i, kind in enumerate(events)]))
    assert [g.reason for g in occurrences(rows)] == list(events)
    assert all(fit(g, "raw_ms") is None for g in occurrences(rows))
    for changes in ({"silent": 1}, {"status": -1}, {"paused": 1}, {"playing": 0},
                    {"age_ms": 251}, {"sample_epoch": 2}, {"sample": 0}, {"read_ms": 30}):
        bad = occurrences(parse([line(1, 0, "start"), line(2, 2, **changes)]))
        assert not bad[-1].rows
    assert len(occurrences(parse(lines + [lines[-1]]))[-1].rows) == 10
    for key in ("epoch", "output", "rate", "speed", "dropped", "uri"):
        changed = "different" if key == "uri" else 2
        gs = occurrences(parse([line(1, 0, "start"), line(2, 2, **{key: changed})]))
        assert gs[-1].reason == key
    # A new process, unavailable lyrics, nonfinite data and empty captures.
    assert occurrences([]) == []
    assert len(list(parse(["\x1b[32m" + lines[0] + "\x1b[0m"]))) == 1
    # Drift-free noise has a known fixed-offset RMS; a silent event cluster keeps its labels.
    noisy = [line(0, 0, "start")]
    noisy += [line(i, i, offset=2 + (0.01 if i % 2 else -0.01)) for i in range(1, 11)]
    noise_fit = fit(occurrences(parse(noisy))[0], "raw_ms")
    assert abs(noise_fit["a_ms"] - 2000) < 1e-6 and abs(noise_fit["jitter_ms"] - 10) < 1e-6
    clustered = lines[:11] + [line(12, 11, "pause"), line(13, 12, "resume")]
    clustered += [line(i + 3, i, offset=3) for i in range(13, 23)]
    stream = io.StringIO()
    report(occurrences(parse(clustered)), stream)
    assert "across=pause+resume" in stream.getvalue()
    restarted = lines[:11] + [line(i + 1, i, session=2) for i in range(11)]
    stream = io.StringIO()
    report(occurrences(parse(restarted)), stream)
    assert "jump_ms=unknown across=baseline" in stream.getvalue().split("session=2", 1)[1]
    gs = occurrences(parse([line(i, i, karaoke_uri="other") for i in range(5)]))
    assert fit(gs[0], "karaoke_ms") is None
    try:
        list(parse([line(1, 0, raw_ms="nan")]))
        raise AssertionError("nonfinite input accepted")
    except ValueError:
        pass
    print("SELFTEST PASS")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", nargs="?", help="syslog file, or - for stdin")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--settle", type=float, default=1.0, help="seconds excluded after each boundary (default 1)")
    parser.add_argument("--max-age-ms", type=float, default=250.0)
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return
    if not args.capture:
        parser.error("give a capture or --selftest")
    if not all(math.isfinite(v) and v >= 0 for v in (args.settle, args.max_age_ms)):
        parser.error("limits must be nonnegative")
    try:
        if args.capture == "-":
            groups = occurrences(parse(sys.stdin), args.settle, args.max_age_ms)
        else:
            with Path(args.capture).open(errors="replace") as source:
                groups = occurrences(parse(source), args.settle, args.max_age_ms)
        if not groups:
            raise ValueError("no lossless-anchor lines found")
        report(groups)
    except (ValueError, OSError) as error:
        parser.exit(1, f"anchor: {error}\n")


if __name__ == "__main__":
    main()
