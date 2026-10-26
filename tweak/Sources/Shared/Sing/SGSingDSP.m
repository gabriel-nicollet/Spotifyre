#include "SGSingDSP.h"
#include <math.h>
#include <stdatomic.h>

static const double kLevelRampSeconds = 0.030;
static const double kBypassRampSeconds = 0.120;
static atomic_bool sg_spatialVoice = false;
static atomic_int sg_spatialAzimuthMilliDegrees = 0;
static atomic_int sg_spatialReverb = 250, sg_spatialEcho = 100, sg_spatialWidth = 350, sg_spatialDistance = 200;
static atomic_bool sg_vocalEQEnabled = false;
static atomic_int sg_eqLowMilliDB = 0, sg_eqMidMilliDB = 0, sg_eqHighMilliDB = 0, sg_vocalGainMilliDB = 0;

static int decibelsMilli(float value, float minimum, float maximum) {
    if (!isfinite(value)) value = 0;
    value = fmaxf(minimum, fminf(maximum, value));
    return (int)lrintf(value * 1000.0f);
}

void SGSingDSPSetVocalEQ(bool enabled, float lowDB, float midDB, float highDB) {
    atomic_store_explicit(&sg_eqLowMilliDB, decibelsMilli(lowDB, -12, 12), memory_order_relaxed);
    atomic_store_explicit(&sg_eqMidMilliDB, decibelsMilli(midDB, -12, 12), memory_order_relaxed);
    atomic_store_explicit(&sg_eqHighMilliDB, decibelsMilli(highDB, -12, 12), memory_order_relaxed);
    atomic_store_explicit(&sg_vocalEQEnabled, enabled, memory_order_relaxed);
}

void SGSingDSPSetVocalGainDB(float decibels) {
    atomic_store_explicit(&sg_vocalGainMilliDB, decibelsMilli(decibels, -18, 12), memory_order_relaxed);
}

void SGSingDSPSetSpatialParameters(float reverb, float echo, float width, float distance) {
    float values[] = {reverb, echo, width, distance};
    atomic_int *slots[] = {&sg_spatialReverb, &sg_spatialEcho, &sg_spatialWidth, &sg_spatialDistance};
    for (int i = 0; i < 4; i++) {
        float v = isfinite(values[i]) ? fmaxf(0.0f, fminf(1.0f, values[i])) : 0.0f;
        atomic_store_explicit(slots[i], (int)lrintf(v * 1000.0f), memory_order_relaxed);
    }
}

void SGSingDSPSetSpatialVoice(bool enabled) {
    atomic_store_explicit(&sg_spatialVoice, enabled, memory_order_relaxed);
    if (!enabled) atomic_store_explicit(&sg_spatialAzimuthMilliDegrees, 0, memory_order_relaxed);
}
bool SGSingDSPSpatialVoice(void) { return atomic_load_explicit(&sg_spatialVoice, memory_order_relaxed); }
void SGSingDSPSetSpatialAzimuthDegrees(float degrees) {
    if (!isfinite(degrees)) degrees = 0;
    if (degrees < -75.0f) degrees = -75.0f;
    if (degrees > 75.0f) degrees = 75.0f;
    atomic_store_explicit(&sg_spatialAzimuthMilliDegrees, (int)lrintf(degrees * 1000.0f), memory_order_relaxed);
}

static void ramp(SGSingMixer *m,
                 float to,
                 float instrumentalTo,
                 double seconds) {
    m->targetGain = to;
    m->instrumentalTarget = instrumentalTo;
    m->remaining = (uint32_t)fmax(1, m->sampleRate * seconds);
    m->step = (to - m->gain) / m->remaining;
    m->instrumentalStep =
        (instrumentalTo - m->instrumental) / m->remaining;
}

static void apply(SGSingMixer *m, float level, bool vocalsOnly) {
    (void)vocalsOnly;

    float value = SGSingClampLevel(level);

    float vocal;
    float instrumental;

    if (value <= 1.0f) {
        // 0% = instrumental only
        // 100% = original mix
        //
        // Vocal gain rises from 0 → 1.
        // Instrumental stays at 1.
        vocal = value;
        instrumental = 1.0f;
    } else {
        // 100% = original mix
        // 110% = vocals only
        //
        // Vocal stays at full level.
        // Instrumental falls from 1 → 0.
        vocal = 1.0f;
        instrumental = 1.0f - ((value - 1.0f) / 0.1f);
    }

    ramp(m, vocal, instrumental, kLevelRampSeconds);
}

void SGSingMixerInit(SGSingMixer *m, double rate, float level) {
    float value = SGSingClampLevel(level);

    float vocal;
    float instrumental;

    if (value <= 1.0f) {
        vocal = value;
        instrumental = 1.0f;
    } else {
        vocal = 1.0f;
        instrumental = 1.0f - ((value - 1.0f) / 0.1f);
    }

    *m = (SGSingMixer){
        .gain = vocal,
        .targetGain = vocal,
        .instrumental = instrumental,
        .instrumentalTarget = instrumental,
        .sampleRate =
            isfinite(rate) && rate >= 8000 && rate <= 192000
                ? rate
                : 44100
    };
}

void SGSingMixerSetLevel(SGSingMixer *m, float level) {
    apply(m, level, m->vocalsOnly);
}

void SGSingMixerSetVocalsOnly(SGSingMixer *m,
                               float level,
                               bool vocalsOnly) {
    apply(m, level, vocalsOnly);
}

void SGSingMixerBypass(SGSingMixer *m) {
    ramp(m, 1, 1, kBypassRampSeconds);
}

void SGSingMixerProcess(SGSingMixer *m,
                        const float *original,
                        const float *vocals,
                        float *out,
                        uint32_t frames) {
    const bool spatial = SGSingDSPSpatialVoice();
    const float targetAzimuth = spatial
        ? (float)atomic_load_explicit(&sg_spatialAzimuthMilliDegrees, memory_order_relaxed) * (float)(3.14159265358979323846 / 180000.0)
        : 0.0f;
    const float azimuthLimit = 1.3090f; // 75 degrees
    const float alpha = (float)(1.0 - exp(-1.0 / (m->sampleRate * 0.020)));
    const uint32_t maxITD = (uint32_t)fmin(31.0, m->sampleRate * 0.00065);
    // Keep the reflections early so the centered singer reads in front instead of as a late, rear echo.
    const uint32_t roomDelayL = (uint32_t)fmin(1023.0, m->sampleRate * 0.002);
    const uint32_t roomDelayR = (uint32_t)fmin(1023.0, m->sampleRate * 0.003);
    const float reverb = (float)atomic_load_explicit(&sg_spatialReverb, memory_order_relaxed) / 1000.0f;
    const float echo = (float)atomic_load_explicit(&sg_spatialEcho, memory_order_relaxed) / 1000.0f;
    const float width = (float)atomic_load_explicit(&sg_spatialWidth, memory_order_relaxed) / 1000.0f;
    const float distance = (float)atomic_load_explicit(&sg_spatialDistance, memory_order_relaxed) / 1000.0f;
    const bool eqEnabled = spatial && atomic_load_explicit(&sg_vocalEQEnabled, memory_order_relaxed);
    const float lowGain = eqEnabled ? powf(10.0f, (float)atomic_load_explicit(&sg_eqLowMilliDB, memory_order_relaxed) / 20000.0f) : 1.0f;
    const float midGain = eqEnabled ? powf(10.0f, (float)atomic_load_explicit(&sg_eqMidMilliDB, memory_order_relaxed) / 20000.0f) : 1.0f;
    const float highGain = eqEnabled ? powf(10.0f, (float)atomic_load_explicit(&sg_eqHighMilliDB, memory_order_relaxed) / 20000.0f) : 1.0f;
    const float vocalGain = spatial ? powf(10.0f, (float)atomic_load_explicit(&sg_vocalGainMilliDB, memory_order_relaxed) / 20000.0f) : 1.0f;
    const float eqLowAlpha = (float)(1.0 - exp(-2.0 * 3.14159265358979323846 * 250.0 / m->sampleRate));
    const float eqHighAlpha = (float)(1.0 - exp(-2.0 * 3.14159265358979323846 * 3000.0 / m->sampleRate));
    const uint32_t echoDelay = (uint32_t)fmin(16383.0, m->sampleRate * (0.10 + 0.20 * echo));

    for (uint32_t i = 0; i < frames; i++) {
        if (m->remaining) {
            m->gain += m->step;
            m->instrumental += m->instrumentalStep;
            if (!--m->remaining) {
                m->gain = m->targetGain;
                m->instrumental = m->instrumentalTarget;
            }
        }

        float sourceL = isfinite(original[(size_t)i * 2]) ? original[(size_t)i * 2] : 0;
        float sourceR = isfinite(original[(size_t)i * 2 + 1]) ? original[(size_t)i * 2 + 1] : 0;
        float vocalL = isfinite(vocals[(size_t)i * 2]) ? vocals[(size_t)i * 2] : 0;
        float vocalR = isfinite(vocals[(size_t)i * 2 + 1]) ? vocals[(size_t)i * 2 + 1] : 0;
        float spatialL = vocalL, spatialR = vocalR;

        if (eqEnabled) {
            m->eqLowL += eqLowAlpha * (vocalL - m->eqLowL);
            m->eqLowR += eqLowAlpha * (vocalR - m->eqLowR);
            m->eqHighL += eqHighAlpha * (vocalL - m->eqHighL);
            m->eqHighR += eqHighAlpha * (vocalR - m->eqHighR);
            float midL = m->eqHighL - m->eqLowL, midR = m->eqHighR - m->eqLowR;
            float highL = vocalL - m->eqHighL, highR = vocalR - m->eqHighR;
            vocalL = m->eqLowL * lowGain + midL * midGain + highL * highGain;
            vocalR = m->eqLowR * lowGain + midR * midGain + highR * highGain;
            spatialL = vocalL; spatialR = vocalR;
        }

        if (spatial) {
            // Smooth head motion to avoid zipper noise. A mono source is panned in the
            // listener's frame; the short far-ear delay and quiet reflections add depth.
            m->spatialAzimuth += (targetAzimuth - m->spatialAzimuth) * alpha;
            if (m->spatialAzimuth < -azimuthLimit) m->spatialAzimuth = -azimuthLimit;
            if (m->spatialAzimuth > azimuthLimit) m->spatialAzimuth = azimuthLimit;
            float mono = 0.5f * (vocalL + vocalR) * (0.96f - distance * 0.30f);
            float side = 0.5f * (vocalL - vocalR) * width;
            float pan = sinf(m->spatialAzimuth) / sinf(azimuthLimit);
            if (pan < -1) pan = -1;
            if (pan > 1) pan = 1;
            float dryL = (mono + side) * sqrtf(0.5f * (1.0f - pan));
            float dryR = (mono - side) * sqrtf(0.5f * (1.0f + pan));

            uint32_t delayL = m->spatialAzimuth > 0 ? maxITD : 0;
            uint32_t delayR = m->spatialAzimuth < 0 ? maxITD : 0;
            uint32_t write = m->spatialITDIndex;
            m->spatialITD[write] = mono;
            uint32_t readL = (write + 64 - delayL) & 63;
            uint32_t readR = (write + 64 - delayR) & 63;
            float delayedL = m->spatialITD[readL];
            float delayedR = m->spatialITD[readR];
            m->spatialITDIndex = (write + 1) & 63;
            // Blend the delayed far ear very lightly so localization stays stable.
            if (delayL) dryL = dryL * 0.92f + delayedL * sqrtf(0.5f * (1.0f - pan)) * 0.08f;
            if (delayR) dryR = dryR * 0.92f + delayedR * sqrtf(0.5f * (1.0f + pan)) * 0.08f;

            uint32_t roomAt = m->spatialRoomIndex;
            uint32_t tapL = (roomAt + 1024 - roomDelayL) & 1023;
            uint32_t tapR = (roomAt + 1024 - roomDelayR) & 1023;
            float reflectionL = m->spatialRoomL[tapL];
            float reflectionR = m->spatialRoomR[tapR];
            m->spatialRoomL[roomAt] = dryL + reflectionL * (0.12f + reverb * 0.38f);
            m->spatialRoomR[roomAt] = dryR + reflectionR * (0.12f + reverb * 0.38f);
            m->spatialRoomIndex = (roomAt + 1) & 1023;
            uint32_t echoAt = m->spatialEchoIndex;
            uint32_t echoTap = (echoAt + 16384 - echoDelay) & 16383;
            float echoL = m->spatialEchoL[echoTap], echoR = m->spatialEchoR[echoTap];
            m->spatialEchoL[echoAt] = dryL + echoL * 0.28f;
            m->spatialEchoR[echoAt] = dryR + echoR * 0.28f;
            m->spatialEchoIndex = (echoAt + 1) & 16383;
            spatialL = dryL + reflectionL * (0.04f + reverb * 0.20f) + echoL * echo * 0.45f;
            spatialR = dryR + reflectionR * (0.04f + reverb * 0.20f) + echoR * echo * 0.45f;
        }

        // Remove the original separated vocal per channel, then add the processed vocal.
        // This keeps the instrumental's stereo image intact instead of centering its side signal.
        float valueL = m->instrumental * (sourceL - (eqEnabled ? (isfinite(vocals[(size_t)i * 2]) ? vocals[(size_t)i * 2] : 0) : vocalL)) + m->gain * vocalGain * spatialL;
        float valueR = m->instrumental * (sourceR - (eqEnabled ? (isfinite(vocals[(size_t)i * 2 + 1]) ? vocals[(size_t)i * 2 + 1] : 0) : vocalR)) + m->gain * vocalGain * spatialR;
        out[(size_t)i * 2] = fmaxf(-1, fminf(1, valueL));
        out[(size_t)i * 2 + 1] = fmaxf(-1, fminf(1, valueR));
    }
}
