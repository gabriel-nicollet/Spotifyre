// Sing's separator: two seconds of a song in, its vocals out, through the voice model (Mel-Band RoFormer
// with KimberleyJensen's vocal checkpoint, MIT; Sing.h says where it comes from). The model is the spectral
// core only, so the STFT around it is done here, as the checkpoint's reference implementation does it
// (its configs/config_vocals_mel_band_roformer.yaml, and model.mil read for the layout):
//
//   44.1 kHz stereo, n_fft 2048, hop 441, a periodic Hann window of 2048, unnormalized, centered with
//   reflect padding (torch.stft's defaults), so two seconds (88200 frames) make 201 frames of 1025 bins.
//   The model's `spectrum` and `vocals_spectrum` are float32 [1, 2050, 201, 2]: axis 1 is bin-major with
//   the two channels interleaved (bin f of channel c at 2f + c, which its band split's gather indices
//   pair up), the last axis real then imaginary (its complex mask multiply reads them so).
//
// The vocals come back from the model's complex mask times the spectrum, through the inverse STFT
// (torch.istft: overlap-add of the windowed frames divided by the window's squared sum).
//
// Two copies of the model can stand behind one separator: the CPU's, which it is made with, and a faster one (the
// Neural Engine's) handed over once it is loaded and warm, which then takes every window, in the background too. A
// window the faster copy fails is done again on the CPU's, and the faster copy is not used again until another is
// handed over (Sing.x drops it for the launch). The first windows on each copy are logged with their time.
//
// Threading: one separator is used by one thread at a time (its buffers are its own); the faster copy can be set from
// any thread.
#import <Foundation/Foundation.h>

@class MLModel;

enum {
    kSGSingRate = 44100,
    kSGSingWindowFrames = 88200,   // two seconds, what the model takes
    kSGSingFFT = 2048,
    kSGSingHop = 441,
    kSGSingBins = kSGSingFFT / 2 + 1,
    kSGSingSTFTFrames = kSGSingWindowFrames / kSGSingHop + 1,
    kSGSingSpectrumFloats = kSGSingBins * 2 * kSGSingSTFTFrames * 2,
};

// The thermal state in a word, for the log.
const char *SGSingThermalName(void);
// The process's memory for the log (TASK_VM_INFO): its footprint (phys_footprint, what iOS holds against its limit) and
// what is resident, the model's weights mapped from their file with it.
NSString *SGSingMemoryText(void);

typedef struct {
    unsigned long long windows[2], fallbacks;   // [0] the CPU's copy, [1] the faster one
    double averageMS[2];
    bool fast;                                  // the last window went to the faster copy
    bool fastFailed;                            // the faster copy now in failed a window, and is not used again
} SGSingSeparatorStats;

@interface SGSingSeparator : NSObject
// Nil `model` makes one that only does the STFT, for the harness.
- (instancetype)initWithModel:(MLModel *)model;
// The faster copy, already warm, and the name the log gives it; nil takes it away.
- (void)setFastModel:(MLModel *)model named:(NSString *)name;
- (SGSingSeparatorStats)stats;
// One prediction of silence on `model`, which Core ML spends allocating and specializing, so the first real window
// does not; its time in seconds, or a negative number and `error` when the model failed or answered in a shape the
// separator does not read.
+ (double)warmUp:(MLModel *)model error:(NSError **)error;
// The window's spectrum in the model's layout, `spectrum` holding kSGSingSpectrumFloats.
- (void)analyzeLeft:(const float *)left right:(const float *)right into:(float *)spectrum;
// The inverse: kSGSingWindowFrames frames per channel out of a spectrum in the model's layout.
- (void)synthesize:(const float *)spectrum left:(float *)left right:(float *)right;
// The vocals of kSGSingWindowFrames frames of stereo; NO and `error` when the model failed.
- (BOOL)separateLeft:(const float *)left right:(const float *)right vocalsLeft:(float *)vocalsLeft
         vocalsRight:(float *)vocalsRight error:(NSError **)error;
@end
