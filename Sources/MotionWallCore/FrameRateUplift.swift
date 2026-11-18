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
    private let converter: PixelConverter
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

        converter = try PixelConverter()
        sourcePool = try createPixelBufferPool(
            configuration.sourcePixelBufferAttributes, format: format, width: width, height: height)
        destinationPool = try createPixelBufferPool(
            configuration.destinationPixelBufferAttributes, format: format, width: width, height: height)
        self.outputPool = outputPool
        fallbackDuration = CMTime(seconds: 1 / sourceFrameRate, preferredTimescale: 600_000)
        try processor.start(configuration)
    }

    deinit {
        processor.endSession()
    }

    func add(_ buffer: CVPixelBuffer, at time: CMTime, duration: CMTime) throws -> [TimedFrame] {
        let converted = try converter.convert(buffer, using: sourcePool)
        guard let processorFrame = VTFrameProcessorFrame(buffer: converted, presentationTimeStamp: time) else {
            throw MotionWallError.frameProcessingFailed("the frame at \(time.seconds)s was rejected")
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
            let destination = try makeBuffer(from: destinationPool)
            CVBufferPropagateAttachments(previous.frame.buffer, destination)
            guard let frame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time) else {
                throw MotionWallError.pixelBufferAllocation
            }
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
        else { throw MotionWallError.frameProcessingFailed("the interpolation parameters were rejected") }
        try processor.processAndWait(parameters)

        for item in interpolated {
            let frame = frames[item.index]
            frames[item.index] = TimedFrame(
                buffer: try converter.convert(item.destination.buffer, using: outputPool),
                time: frame.time,
                duration: frame.duration
            )
        }
        return frames
    }
}
