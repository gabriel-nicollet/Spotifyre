// Sing's separator: the Mel-Band RoFormer vocal model (harness/sing/model.json has its provenance) run by
// Core ML on this iPhone. The compiled graph is the model's spectral core alone: the worker takes the STFT
// and its inverse with Accelerate (SGStemSpectralDSP.swift), and Core ML turns one two-second spectrum into
// the spectrum of its vocals. Each model is loaded for CPU, which iOS allows in the background, and for its
// foreground accelerator: the GPU for the full and light exports, or Neural Engine for the ANE export. Nothing
// here runs on the render thread or on UIKit's, and no audio leaves the process.
import CoreML
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum SGStemError: Error {
    case invalidModel, invalidInput, invalidOutput
}

// The one shape the model has. The C side (Shared/Sing/SGSingFormat.h) names the same window, and
// SGStemWorkerStart checks the loaded model against the window it is given.
enum SGStemShape {
    static let fftSize = 2048, stftHop = 441, stftFrames = 201
    static let bins = fftSize / 2 + 1
    static let windowFrames = (stftFrames - 1) * stftHop   // 88200, two seconds at 44.1 kHz
    // [1, real and imaginary of each bin for each channel, frame, 2], float32 in and out.
    static let spectrum: [Int] = [1, bins * 2, stftFrames, 2]
    static let spectrumCount = spectrum.reduce(1, *)
}

@available(iOS 27.0, macOS 27.0, *)
actor SGStemSeparator {
    let windowFrames = SGStemShape.windowFrames
    private let cpu: MLModel
    private var gpu: MLModel?            // nil when acceleration could not be loaded; CPU then does everything
    private var gpuFailed = false        // an accelerated prediction failed since Spotify was last inactive
    private var lastAccelerated: Bool?
    private let dsp: SGStemSpectralDSP
    private let tensor: MLMultiArray
    private let provider: MLDictionaryFeatureProvider
    private let inputType: MLMultiArrayDataType
    private let outputType: MLMultiArrayDataType
    private var running = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(modelURL: URL) async throws {
        let cpuOnly = MLModelConfiguration()
        cpuOnly.computeUnits = .cpuOnly
        let cpu = try await MLModel.load(contentsOf: modelURL, configuration: cpuOnly)
        try Task.checkCancellation()
        let shape = SGStemShape.spectrum.map(NSNumber.init(value:))
        let description = cpu.modelDescription
        guard description.stateDescriptionsByName.isEmpty,
              description.inputDescriptionsByName.count == 1, description.outputDescriptionsByName.count == 1,
              let input = description.inputDescriptionsByName["spectrum"]?.multiArrayConstraint,
              let output = description.outputDescriptionsByName["vocals_spectrum"]?.multiArrayConstraint,
              input.shape == shape, output.shape == shape,
              [MLMultiArrayDataType.float32, .float16].contains(input.dataType),
              [MLMultiArrayDataType.float32, .float16].contains(output.dataType) else { throw SGStemError.invalidModel }
        let tensor = try MLMultiArray(shape: shape, dataType: input.dataType)
        guard tensor.strides.map(\.intValue) == Self.strides else { throw SGStemError.invalidInput }
        self.tensor = tensor
        self.provider = try MLDictionaryFeatureProvider(dictionary: ["spectrum": tensor])
        self.inputType = input.dataType
        self.outputType = output.dataType
        self.cpu = cpu
        self.dsp = try SGStemSpectralDSP()
        let accelerated = MLModelConfiguration()
        // The ANE export is the same separator weights laid out for the Neural Engine; the two
        // other exports use the GPU when available. CPU remains the safe background path.
        accelerated.computeUnits = modelURL.lastPathComponent.contains("ane") ? .cpuAndNeuralEngine : .cpuAndGPU
        // Without an accelerated copy the CPU one still does the work, only more slowly.
        do { self.gpu = try await MLModel.load(contentsOf: modelURL, configuration: accelerated) }
        catch {
            try Task.checkCancellation()
            NSLog("[spotifyglass] Sing foreground acceleration unavailable: %@", String(describing: error))
        }
    }

    // A packed row-major tensor: what encode writes and decode reads.
    private static let strides: [Int] = SGStemShape.spectrum.indices.map {
        SGStemShape.spectrum[($0 + 1)...].reduce(1, *)
    }

    // Core ML's first prediction allocates and specializes beyond loading, so it is paid here, before the
    // worker says Ready, while Spotify still plays its own audio. Both copies are warmed, so going to the
    // background or coming back never meets a cold model in the middle of the reduced mix.
    func warmUp() async throws {
        try encode([Float](repeating: 0, count: windowFrames * 2))
        _ = try predict(accelerated: false)
        if gpu != nil, await foreground() { _ = try predict(accelerated: true) }
    }

    // One window of stereo interleaved PCM in, its vocals out; the instrumental is the mix less these. The
    // streaming worker overlaps consecutive windows itself (SGStemWindowProcessor.swift).
    func vocals(for pcm: [Float]) async throws -> [Float] {
        guard pcm.count == windowFrames * 2, pcm.allSatisfy(\.isFinite) else { throw SGStemError.invalidInput }
        // Asking UIKit whether Spotify is active suspends this actor, and another window may come in
        // meanwhile. The two share one input tensor, so they take turns.
        await acquire()
        defer { release() }
        try Task.checkCancellation()
        let active = gpu != nil ? await foreground() : false
        if !active { gpuFailed = false }
        try encode(pcm)
        let accelerated = active && !gpuFailed
        if lastAccelerated != accelerated {
            NSLog("[spotifyglass] Sing Core ML compute policy: %@", accelerated ? "foreground accelerator" : "CPU only")
            lastAccelerated = accelerated
        }
        return try predict(accelerated: accelerated)
    }

    private func acquire() async {
        if running { await withCheckedContinuation { waiters.append($0) } }
        else { running = true }
    }

    private func release() {
        if waiters.isEmpty { running = false }
        else { waiters.removeFirst().resume() }
    }

    private func foreground() async -> Bool {
        #if canImport(UIKit)
        return await MainActor.run { UIApplication.shared.applicationState == .active }
        #else
        return true
        #endif
    }

    private func encode(_ pcm: [Float]) throws {
        var values = [Float](repeating: 0, count: tensor.count)
        try values.withUnsafeMutableBufferPointer { try dsp.encode(pcm, into: $0) }
        if inputType == .float32 {
            values.withUnsafeBufferPointer { source in
                tensor.dataPointer.copyMemory(from: source.baseAddress!, byteCount: values.count * MemoryLayout<Float>.size)
            }
        } else {
            let destination = tensor.dataPointer.assumingMemoryBound(to: Float16.self)
            for index in values.indices { destination[index] = Float16(values[index]) }
        }
    }

    private func predict(accelerated: Bool) throws -> [Float] {
        try Task.checkCancellation()
        let result: MLFeatureProvider
        if accelerated, let gpu {
            do { result = try gpu.prediction(from: provider) }
            catch {
                try Task.checkCancellation()
                // Going to the background can race the foreground check, and iOS then refuses the GPU.
                // The same window goes to the warm CPU model with its timestamp kept, and the GPU is not
                // asked again until Spotify has been inactive.
                gpuFailed = true
                NSLog("[spotifyglass] Sing using CPU after foreground prediction failed: %@", String(describing: error))
                result = try cpu.prediction(from: provider)
            }
        } else { result = try cpu.prediction(from: provider) }
        try Task.checkCancellation()
        guard let output = result.featureValue(for: "vocals_spectrum")?.multiArrayValue,
              output.shape.map(\.intValue) == SGStemShape.spectrum, output.dataType == outputType,
              output.strides.map(\.intValue) == Self.strides else { throw SGStemError.invalidOutput }
        if outputType == .float32 {
            return try dsp.decode(UnsafeBufferPointer(start: output.dataPointer.assumingMemoryBound(to: Float.self), count: output.count))
        }
        let half = output.dataPointer.assumingMemoryBound(to: Float16.self)
        var values = [Float](repeating: 0, count: output.count)
        for index in values.indices { values[index] = Float(half[index]) }
        return try values.withUnsafeBufferPointer { try dsp.decode($0) }
    }
}
