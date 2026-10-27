// The Visualizer's spectrum (Redesigned/Player/SGRSpectrum.m, as the tweak compiles it) on the Mac: tones and
// noise handed over in IO buffers of 1024 at an output's rate, the way PlayerVisualiser.x gets them through
// AudioEffects.x's reader, and each check printed with ok or WRONG.
//
//     ./build.sh && build/spectrum
#import <Foundation/Foundation.h>
#import "Redesigned/Player/SGRSpectrum.h"

static int checks, right;

static void check(BOOL ok, NSString *what) {
    checks++;
    right += ok;
    printf("%s  %s\n", ok ? "ok   " : "WRONG", what.UTF8String);
}

// `seconds` of a sine of `amplitude` at `hz` (0: silence; negative: white noise of that amplitude), fed in
// buffers of 1024. Answers how many analyses there have been.
static uint64_t feed(double hz, float amplitude, double rate, double seconds) {
    static double phase;
    float buffer[1024];
    uint32_t total = (uint32_t)(seconds * rate);
    for (uint32_t done = 0; done < total; done += 1024) {
        for (int i = 0; i < 1024; i++) {
            if (hz > 0) {
                buffer[i] = amplitude * (float)sin(phase);
                phase += 2 * M_PI * hz / rate;
            } else if (hz < 0) {
                buffer[i] = amplitude * (2 * (float)arc4random_uniform(1 << 16) / (1 << 16) - 1);
            } else {
                buffer[i] = 0;
            }
        }
        SGRSpectrumFeed(buffer, 1024, rate);
    }
    float levels[SGRSpectrumBands];
    return SGRSpectrumRead(levels);
}

// The loudest band, its level, and the loudest more than one band away from it (a tone near an edge spills into
// its neighbor).
static int loudest(const float *levels, float *level, float *outside) {
    int best = 0;
    for (int i = 1; i < SGRSpectrumBands; i++) if (levels[i] > levels[best]) best = i;
    *level = levels[best];
    *outside = SGRSpectrumFloor;
    for (int i = 0; i < SGRSpectrumBands; i++) if (abs(i - best) > 1) *outside = fmaxf(*outside, levels[i]);
    return best;
}

static void tone(double hz, float amplitude, double rate, int band, float expected, float within) {
    feed(hz, amplitude, rate, 0.5);
    float levels[SGRSpectrumBands], level, outside;
    SGRSpectrumRead(levels);
    int best = loudest(levels, &level, &outside);
    check(best == band && fabsf(level - expected) < within && outside < level - 30,
          [NSString stringWithFormat:@"%.0f Hz at %.1f kHz: band %d (want %d) at %.1f dB (want %.0f), the rest %.1f dB under",
           hz, rate / 1000, best, band, level, expected, level - outside]);
}

int main(void) {
    @autoreleasepool {
        float levels[SGRSpectrumBands];
        check(feed(1000, 1, 48000, 0.5) == 0, @"nothing analyzed before SGRSpectrumPrepare");
        SGRSpectrumPrepare();
        SGRSpectrumPrepare();
        SGRSpectrumRead(levels);
        check(levels[0] == SGRSpectrumFloor && levels[SGRSpectrumBands - 1] == SGRSpectrumFloor, @"every band at the floor to begin with");

        // The bands are spaced by (14000/50)^(1/24): 1 kHz is in band 12, 56 Hz in band 0, 10 kHz in band 22. The
        // lowest bands are a bin or two wide, narrower than a tone's spread under the window, so they keep only
        // part of it.
        tone(1000, 1, 48000, 12, 0, 1);
        tone(1000, 0.1f, 48000, 12, -20, 1);
        tone(56, 0.5f, 48000, 0, -6, 3);
        tone(10000, 0.5f, 48000, 22, -6, 1);
        tone(1000, 1, 44100, 12, 0, 1);
        tone(56, 0.5f, 44100, 0, -6, 3);

        uint64_t before = feed(0, 0, 44100, 0.01);
        uint64_t after = feed(0, 0, 44100, 0.5);
        SGRSpectrumRead(levels);
        float loudestSilence = SGRSpectrumFloor;
        for (int i = 0; i < SGRSpectrumBands; i++) loudestSilence = fmaxf(loudestSilence, levels[i]);
        check(after > before && loudestSilence == SGRSpectrumFloor, @"silence: still analyzed, every band at the floor");

        // White noise has as much power per hertz, so a band's level rises with its width: about 3 dB an octave,
        // and bands 8 to 20 span about 3.9 octaves. One analysis of noise over a narrow band swings by a few dB,
        // so the rise is averaged over a second of them.
        feed(-1, 0.5f, 48000, 0.2);
        float rise = 0;
        for (int i = 0; i < 48; i++) {
            feed(-1, 0.5f, 48000, 1024 / 48000.0);
            SGRSpectrumRead(levels);
            rise += (levels[20] - levels[8]) / 48;
        }
        check(rise > 9 && rise < 15, [NSString stringWithFormat:@"white noise rises %.1f dB from band 8 to 20 (want about 12)", rise]);

        // About 47 analyses a second at 48 kHz: one every 1024 samples once the ring is full.
        uint64_t start = feed(0, 0, 48000, 0.01);
        uint64_t end = feed(0, 0, 48000, 1);
        check(end - start >= 45 && end - start <= 48, [NSString stringWithFormat:@"%llu analyses in a second at 48 kHz", end - start]);

        printf("spectrum checks: %d of %d right -- %s\n", right, checks, right == checks ? "PASS" : "FAIL");
        return right == checks ? 0 : 1;
    }
}
