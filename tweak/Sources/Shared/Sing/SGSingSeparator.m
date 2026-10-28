#import <Accelerate/Accelerate.h>
#import <CoreML/CoreML.h>
#import <mach/mach.h>
#import <os/lock.h>
#import "Core/SGLog.h"
#import "SGSingSeparator.h"

enum {
    kPad = kSGSingFFT / 2,                            // the centering's reflect padding on each side
    kPadded = kSGSingWindowFrames + 2 * kPad,
    kHalf = kSGSingFFT / 2,
};

static NSString *const kInput = @"spectrum", *const kOutput = @"vocals_spectrum";
// This many windows on each copy are logged with their time.
static const unsigned long long kLoggedWindows = 5;

const char *SGSingThermalName(void) {
    switch (NSProcessInfo.processInfo.thermalState) {
        case NSProcessInfoThermalStateNominal: return "nominal";
        case NSProcessInfoThermalStateFair: return "fair";
        case NSProcessInfoThermalStateSerious: return "serious";
        case NSProcessInfoThermalStateCritical: return "critical";
    }
    return "?";
}

NSString *SGSingMemoryText(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return @"footprint unknown";
    return [NSString stringWithFormat:@"footprint %.2f GB, resident %.2f GB", info.phys_footprint / 1e9, info.resident_size / 1e9];
}

// Where bin `bin` of channel `channel` at STFT frame `frame` starts in the model's layout (its real part;
// the imaginary part follows it).
static inline size_t at(int bin, int channel, int frame) {
    return ((size_t)(2 * bin + channel) * kSGSingSTFTFrames + frame) * 2;
}

@implementation SGSingSeparator {
    MLModel *_model;
    os_unfair_lock _lock;        // the faster copy and its name
    MLModel *_fast;
    NSString *_fastName;
    SGSingSeparatorStats _stats; // the worker's; read whole under the lock
    MLMultiArray *_input;
    vDSP_DFT_Setup _forward, _inverse;
    float _window[kSGSingFFT];
    float _envelope[kSGSingWindowFrames];   // 1 / the squared window's overlap-add, per output frame
    float _padded[kPadded];
    float _frame[kSGSingFFT];
    float _real[kHalf], _imag[kHalf], _outReal[kHalf], _outImag[kHalf];
    float _sum[kPadded];
    float *_spectrum, *_vocals;
}

- (instancetype)initWithModel:(MLModel *)model {
    if (!(self = [super init])) return nil;
    _model = model;
    _lock = OS_UNFAIR_LOCK_INIT;
    _forward = vDSP_DFT_zrop_CreateSetup(NULL, kSGSingFFT, vDSP_DFT_FORWARD);
    _inverse = vDSP_DFT_zrop_CreateSetup(_forward, kSGSingFFT, vDSP_DFT_INVERSE);
    _spectrum = calloc(kSGSingSpectrumFloats, sizeof(float));
    _vocals = calloc(kSGSingSpectrumFloats, sizeof(float));
    if (!_forward || !_inverse || !_spectrum || !_vocals) return nil;
    // torch.hann_window's default, periodic: the denominator is N, not N - 1.
    for (int n = 0; n < kSGSingFFT; n++) _window[n] = 0.5f * (1 - cosf(2 * (float)M_PI * n / kSGSingFFT));
    float squares[kSGSingFFT];
    vDSP_vsq(_window, 1, squares, 1, kSGSingFFT);
    memset(_sum, 0, sizeof _sum);
    for (int t = 0; t < kSGSingSTFTFrames; t++) vDSP_vadd(_sum + t * kSGSingHop, 1, squares, 1, _sum + t * kSGSingHop, 1, kSGSingFFT);
    for (int i = 0; i < kSGSingWindowFrames; i++) _envelope[i] = 1 / _sum[i + kPad];
    if (model) {
        NSError *error;
        _input = [[MLMultiArray alloc] initWithDataPointer:_spectrum shape:@[@1, @(2 * kSGSingBins), @(kSGSingSTFTFrames), @2]
                                                  dataType:MLMultiArrayDataTypeFloat32
                                                   strides:@[@(2 * kSGSingBins * kSGSingSTFTFrames * 2), @(kSGSingSTFTFrames * 2), @2, @1]
                                               deallocator:nil error:&error];
        if (!_input) return nil;
    }
    return self;
}

- (void)dealloc {
    if (_inverse) vDSP_DFT_DestroySetup(_inverse);
    if (_forward) vDSP_DFT_DestroySetup(_forward);
    free(_spectrum);
    free(_vocals);
}

#pragma mark - the STFT

- (void)analyzeChannel:(const float *)samples channel:(int)channel into:(float *)spectrum {
    // Reflect padding, the edge sample itself not repeated (torch's "reflect").
    memcpy(_padded + kPad, samples, kSGSingWindowFrames * sizeof(float));
    for (int i = 1; i <= kPad; i++) {
        _padded[kPad - i] = samples[i];
        _padded[kPad + kSGSingWindowFrames - 1 + i] = samples[kSGSingWindowFrames - 1 - i];
    }
    DSPSplitComplex split = {_real, _imag};
    for (int t = 0; t < kSGSingSTFTFrames; t++) {
        vDSP_vmul(_padded + t * kSGSingHop, 1, _window, 1, _frame, 1, kSGSingFFT);
        vDSP_ctoz((const DSPComplex *)_frame, 2, &split, 1, kHalf);
        vDSP_DFT_Execute(_forward, _real, _imag, _outReal, _outImag);
        // vDSP's real transform comes out twice the DFT, with the Nyquist bin's real part where the DC
        // bin's imaginary part would be.
        float *dc = spectrum + at(0, channel, t), *nyquist = spectrum + at(kHalf, channel, t);
        dc[0] = _outReal[0] * 0.5f;
        dc[1] = 0;
        nyquist[0] = _outImag[0] * 0.5f;
        nyquist[1] = 0;
        for (int k = 1; k < kHalf; k++) {
            float *bin = spectrum + at(k, channel, t);
            bin[0] = _outReal[k] * 0.5f;
            bin[1] = _outImag[k] * 0.5f;
        }
    }
}

- (void)analyzeLeft:(const float *)left right:(const float *)right into:(float *)spectrum {
    [self analyzeChannel:left channel:0 into:spectrum];
    [self analyzeChannel:right channel:1 into:spectrum];
}

- (void)synthesizeChannel:(int)channel from:(const float *)spectrum into:(float *)samples {
    memset(_sum, 0, sizeof _sum);
    DSPSplitComplex split = {_outReal, _outImag};
    // The inverse of a true DFT comes out N times the signal, so 1/N with the window applied again.
    float scale = 1.0f / kSGSingFFT;
    for (int t = 0; t < kSGSingSTFTFrames; t++) {
        _real[0] = spectrum[at(0, channel, t)];
        _imag[0] = spectrum[at(kHalf, channel, t)];
        for (int k = 1; k < kHalf; k++) {
            const float *bin = spectrum + at(k, channel, t);
            _real[k] = bin[0];
            _imag[k] = bin[1];
        }
        vDSP_DFT_Execute(_inverse, _real, _imag, _outReal, _outImag);
        vDSP_ztoc(&split, 1, (DSPComplex *)_frame, 2, kHalf);
        vDSP_vmul(_frame, 1, _window, 1, _frame, 1, kSGSingFFT);
        vDSP_vsma(_frame, 1, &scale, _sum + t * kSGSingHop, 1, _sum + t * kSGSingHop, 1, kSGSingFFT);
    }
    vDSP_vmul(_sum + kPad, 1, _envelope, 1, samples, 1, kSGSingWindowFrames);
}

- (void)synthesize:(const float *)spectrum left:(float *)left right:(float *)right {
    [self synthesizeChannel:0 from:spectrum into:left];
    [self synthesizeChannel:1 from:spectrum into:right];
}

#pragma mark - the model

// The model's output into `_vocals`, by its strides, whatever they are and whether it is float32 or 16.
static BOOL readOutput(MLMultiArray *array, float *into) {
    NSArray<NSNumber *> *shape = array.shape, *strides = array.strides;
    if (shape.count != 4 || shape[1].intValue != 2 * kSGSingBins || shape[2].intValue != kSGSingSTFTFrames || shape[3].intValue != 2) return NO;
    MLMultiArrayDataType type = array.dataType;
    if (type != MLMultiArrayDataTypeFloat32 && type != MLMultiArrayDataTypeFloat16) return NO;
    NSInteger s1 = strides[1].integerValue, s2 = strides[2].integerValue, s3 = strides[3].integerValue;
    __block BOOL ok = YES;
    [array getBytesWithHandler:^(const void *bytes, NSInteger size) {
        NSInteger elementSize = type == MLMultiArrayDataTypeFloat32 ? 4 : 2;
        NSInteger last = ((2 * kSGSingBins - 1) * s1 + (kSGSingSTFTFrames - 1) * s2 + s3) * elementSize;
        if (last >= size) {
            ok = NO;
            return;
        }
        BOOL contiguous = s3 == 1 && s2 == 2 && s1 == kSGSingSTFTFrames * 2;
        if (contiguous && type == MLMultiArrayDataTypeFloat32) {
            memcpy(into, bytes, kSGSingSpectrumFloats * sizeof(float));
            return;
        }
        for (NSInteger row = 0; row < 2 * kSGSingBins; row++) {
            for (NSInteger frame = 0; frame < kSGSingSTFTFrames; frame++) {
                for (NSInteger part = 0; part < 2; part++) {
                    NSInteger index = row * s1 + frame * s2 + part * s3;
                    float value = type == MLMultiArrayDataTypeFloat32 ? ((const float *)bytes)[index] : (float)((const _Float16 *)bytes)[index];
                    into[(row * kSGSingSTFTFrames + frame) * 2 + part] = value;
                }
            }
        }
    }];
    return ok;
}

- (void)setFastModel:(MLModel *)model named:(NSString *)name {
    os_unfair_lock_lock(&_lock);
    _fast = model;
    _fastName = name;
    _stats.fastFailed = false;
    _stats.windows[1] = 0;
    _stats.averageMS[1] = 0;
    os_unfair_lock_unlock(&_lock);
}

- (SGSingSeparatorStats)stats {
    os_unfair_lock_lock(&_lock);
    SGSingSeparatorStats stats = _stats;
    os_unfair_lock_unlock(&_lock);
    return stats;
}

// The vocals' spectrum of `features` from `model` into `into`, NO and `error` when it failed.
static BOOL predict(MLModel *model, MLDictionaryFeatureProvider *features, float *into, NSError **error) {
    id<MLFeatureProvider> result = [model predictionFromFeatures:features error:error];
    MLMultiArray *output = [result featureValueForName:kOutput].multiArrayValue;
    if (output && readOutput(output, into)) return YES;
    if (error && !*error) *error = [NSError errorWithDomain:@"SGSing" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The model answered in a shape Karaoke does not read"}];
    return NO;
}

+ (double)warmUp:(MLModel *)model error:(NSError **)error {
    float *silence = calloc(kSGSingSpectrumFloats, sizeof(float)), *out = malloc(kSGSingSpectrumFloats * sizeof(float));
    double took = -1;
    MLMultiArray *input = silence && out ? [[MLMultiArray alloc] initWithDataPointer:silence shape:@[@1, @(2 * kSGSingBins), @(kSGSingSTFTFrames), @2]
                                                                           dataType:MLMultiArrayDataTypeFloat32
                                                                            strides:@[@(2 * kSGSingBins * kSGSingSTFTFrames * 2), @(kSGSingSTFTFrames * 2), @2, @1]
                                                                        deallocator:nil error:error] : nil;
    MLDictionaryFeatureProvider *features = input ? [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{kInput: input} error:error] : nil;
    if (features) {
        CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
        @autoreleasepool {
            if (predict(model, features, out, error)) took = CFAbsoluteTimeGetCurrent() - began;
        }
        // Silence must come back as silence, not as the non-finite numbers a half-precision floor makes of it.
        for (int i = 0; took >= 0 && i < kSGSingSpectrumFloats; i++) {
            if (!isfinite(out[i])) {
                took = -1;
                if (error) *error = [NSError errorWithDomain:@"SGSing" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The model turned silence into numbers that are not finite"}];
            }
        }
    }
    input = nil;   // before the memory it points into
    free(silence);
    free(out);
    return took;
}

// The window's time into the copy's running average, the first windows logged.
- (void)count:(int)copy took:(double)took named:(NSString *)name {
    os_unfair_lock_lock(&_lock);
    unsigned long long n = ++_stats.windows[copy];
    double ms = took * 1000;
    _stats.averageMS[copy] = n == 1 ? ms : _stats.averageMS[copy] * 0.8 + ms * 0.2;
    _stats.fast = copy == 1;
    os_unfair_lock_unlock(&_lock);
    if (n <= kLoggedWindows) SGLog(@"sing: window %llu on the %@ copy took %.0f ms (1500 ms keeps up), thermal state %s", n, name, ms, SGSingThermalName());
    if (n == kLoggedWindows) SGLog(@"sing: memory after %llu windows on the %@ copy: %@", n, name, SGSingMemoryText());
}

- (BOOL)separateLeft:(const float *)left right:(const float *)right vocalsLeft:(float *)vocalsLeft
         vocalsRight:(float *)vocalsRight error:(NSError **)error {
    if (!_model) return NO;
    [self analyzeLeft:left right:right into:_spectrum];
    MLDictionaryFeatureProvider *features = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{kInput: _input} error:error];
    if (!features) return NO;
    os_unfair_lock_lock(&_lock);
    MLModel *fast = _stats.fastFailed ? nil : _fast;
    NSString *fastName = _fastName;
    os_unfair_lock_unlock(&_lock);
    if (fast) {
        CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
        NSError *fastError;
        if (predict(fast, features, _vocals, &fastError)) {
            [self count:1 took:CFAbsoluteTimeGetCurrent() - began named:fastName];
            [self synthesize:_vocals left:vocalsLeft right:vocalsRight];
            return YES;
        }
        os_unfair_lock_lock(&_lock);
        if (_fast == fast) _stats.fastFailed = true;
        _stats.fallbacks++;
        os_unfair_lock_unlock(&_lock);
        SGLog(@"sing: the %@ copy failed a window (%@), so it is done on the CPU's, and the %@ copy is not used again",
              fastName, fastError.localizedDescription, fastName);
    }
    CFAbsoluteTime began = CFAbsoluteTimeGetCurrent();
    if (!predict(_model, features, _vocals, error)) return NO;
    [self count:0 took:CFAbsoluteTimeGetCurrent() - began named:@"CPU"];
    [self synthesize:_vocals left:vocalsLeft right:vocalsRight];
    return YES;
}

@end
