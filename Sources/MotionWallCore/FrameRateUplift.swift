import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum FrameRateUplift {
    public static let frameRate = 120

    public static let isSupported: Bool = {
        guard #available(macOS 15.4, *) else { return false }
        return VTFrameRateConversionConfiguration.isSupported
    }()

    public static func applies(to source: VideoSource) -> Bool {
        source.frameRate < Double(frameRate) - 0.5
    }
}

struct TimedFrame {
    let buffer: CVPixelBuffer
    let time: CMTime
    let duration: CMTime
}

protocol FrameTimeline: AnyObject {
    func add(_ buffer: CVPixelBuffer, at time: CMTime, duration: CMTime) throws -> [TimedFrame]
    func finish() -> [TimedFrame]
}

final class SourceTimeline: FrameTimeline {
    func add(_ buffer: CVPixelBuffer, at time: CMTime, duration: CMTime) -> [TimedFrame] {
        [TimedFrame(buffer: buffer, time: time, duration: duration)]
    }

    func finish() -> [TimedFrame] { [] }
}

@available(macOS 15.4, *)
final class InterpolatedTimeline: FrameTimeline {
    private struct Held {
        let frame: TimedFrame
        let processorFrame: VTFrameProcessorFrame
    }

    private let processor = VTFrameProcessor()
    private let transfer: VTPixelTransferSession
    private let sourcePool: CVPixelBufferPool
    private let destinationPool: CVPixelBufferPool
    private let outputPool: CVPixelBufferPool
    private let step = CMTime(value: 1, timescale: CMTimeScale(FrameRateUplift.frameRate))
    private let fallbackDuration: CMTime
    private var held: Held?
    private var origin = CMTime.zero
    private var emitted: Int64 = 0

    init(width: Int, height: Int, sourceFrameRate: Double, outputPool: CVPixelBufferPool) throws {
        let format = kCVPixelFormatType_64RGBAHalf
        guard VTFrameRateConversionConfiguration.isSupported,
            let configuration = VTFrameRateConversionConfiguration(
                frameWidth: width,
                frameHeight: height,
                usePrecomputedFlow: false,
                qualityPrioritization: .quality,
                revision: VTFrameRateConversionConfiguration.defaultRevision
            )
        else { throw MotionWallError.frameInterpolationUnavailable(width, height) }

        var session: VTPixelTransferSession?
        let status = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault, pixelTransferSessionOut: &session)
        guard status == noErr, let session else { throw MotionWallError.sessionCreate(status) }
        transfer = session

        func pool(_ attributes: [String: Any]) throws -> CVPixelBufferPool {
            var attributes = attributes
            attributes[kCVPixelBufferPixelFormatTypeKey as String] = format
            attributes[kCVPixelBufferWidthKey as String] = width
            attributes[kCVPixelBufferHeightKey as String] = height
            return try createPixelBufferPool(attributes)
        }
        sourcePool = try pool(configuration.sourcePixelBufferAttributes)
        destinationPool = try pool(configuration.destinationPixelBufferAttributes)
        self.outputPool = outputPool
        fallbackDuration = CMTime(seconds: 1 / sourceFrameRate, preferredTimescale: 600_000)

        do {
            try processor.startSession(configuration: configuration)
        } catch {
            throw MotionWallError.frameInterpolationFailed(error.localizedDescription)
        }
    }

    deinit {
        processor.endSession()
        VTPixelTransferSessionInvalidate(transfer)
    }

    func add(_ buffer: CVPixelBuffer, at time: CMTime, duration: CMTime) throws -> [TimedFrame] {
        let converted = try copy(buffer, from: sourcePool)
        guard let processorFrame = VTFrameProcessorFrame(buffer: converted, presentationTimeStamp: time) else {
            throw MotionWallError.frameInterpolationFailed("the frame at \(time.seconds)s was rejected")
        }
        let next = Held(
            frame: TimedFrame(buffer: buffer, time: time, duration: duration),
            processorFrame: processorFrame
        )
        defer { held = next }
        guard let previous = held else {
            origin = time
            return []
        }
        return try frames(between: previous, and: next)
    }

    func finish() -> [TimedFrame] {
        guard let last = held else { return [] }
        let duration = last.frame.duration.isNumeric && last.frame.duration > .zero
            ? last.frame.duration : fallbackDuration
        return slots(before: last.frame.time + duration).map {
            TimedFrame(buffer: last.frame.buffer, time: $0, duration: step)
        }
    }

    private func slots(before end: CMTime) -> [CMTime] {
        var times: [CMTime] = []
        while true {
            let time = origin + CMTimeMultiply(step, multiplier: Int32(emitted))
            guard time < end else { return times }
            times.append(time)
            emitted += 1
        }
    }

    private func frames(between previous: Held, and next: Held) throws -> [TimedFrame] {
        let start = previous.frame.time
        let gap = (next.frame.time - start).seconds
        var frames: [TimedFrame] = []
        var interpolated: [(index: Int, phase: Float, destination: VTFrameProcessorFrame)] = []

        for time in slots(before: next.frame.time) {
            let phase = Float((time - start).seconds / gap)
            if phase < 0.001 {
                frames.append(TimedFrame(buffer: previous.frame.buffer, time: time, duration: step))
                continue
            }
            var destination: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, destinationPool, &destination)
            guard let destination,
                let frame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time)
            else { throw MotionWallError.pixelBufferAllocation }
            interpolated.append((frames.count, phase, frame))
            frames.append(TimedFrame(buffer: destination, time: time, duration: step))
        }
        guard !interpolated.isEmpty else { return frames }

        guard
            let parameters = VTFrameRateConversionParameters(
                sourceFrame: previous.processorFrame,
                nextFrame: next.processorFrame,
                opticalFlow: nil,
                interpolationPhase: interpolated.map(\.phase),
                submissionMode: .sequential,
                destinationFrames: interpolated.map(\.destination)
            )
        else { throw MotionWallError.frameInterpolationFailed("the interpolation parameters were rejected") }
        try process(parameters)

        for item in interpolated {
            let frame = frames[item.index]
            frames[item.index] = TimedFrame(
                buffer: try copy(item.destination.buffer, from: outputPool),
                time: frame.time,
                duration: frame.duration
            )
        }
        return frames
    }

    private func process(_ parameters: VTFrameRateConversionParameters) throws {
        let finished = DispatchSemaphore(value: 0)
        var failure: Error?
        processor.process(parameters: parameters) { _, error in
            failure = error
            finished.signal()
        }
        finished.wait()
        if let failure { throw MotionWallError.frameInterpolationFailed(failure.localizedDescription) }
    }

    private func copy(_ buffer: CVPixelBuffer, from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var target: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &target)
        guard let target else { throw MotionWallError.pixelBufferAllocation }
        let status = VTPixelTransferSessionTransferImage(transfer, from: buffer, to: target)
        guard status == noErr else {
            throw MotionWallError.frameInterpolationFailed("converting a frame failed with status \(status)")
        }
        return target
    }
}

func createPixelBufferPool(_ attributes: [String: Any]) throws -> CVPixelBufferPool {
    var pool: CVPixelBufferPool?
    CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    guard let pool else { throw MotionWallError.pixelBufferAllocation }
    return pool
}
