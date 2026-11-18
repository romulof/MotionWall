import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum SpatialUpscale {
    public static let factor = 4
    public static let maximumOutput = (long: 3840, short: 2160)
    static let maximumInput = (width: 1920, height: 1080)

    public static let isSupported: Bool = {
        guard #available(macOS 26, *) else { return false }
        return VTSuperResolutionScalerConfiguration.isSupported
    }()

    public static func applies(to source: VideoSource) -> Bool {
        Int(source.size.width) <= maximumInput.width && Int(source.size.height) <= maximumInput.height
    }

    public static func outputSize(for source: VideoSource, upscales: Bool) -> (width: Int, height: Int) {
        let width = Double(source.size.width) * Double(upscales ? factor : 1)
        let height = Double(source.size.height) * Double(upscales ? factor : 1)
        let fit = min(
            1,
            Double(maximumOutput.long) / max(width, height),
            Double(maximumOutput.short) / min(width, height)
        )
        guard upscales || fit < 1 else { return (Int(source.size.width), Int(source.size.height)) }
        func even(_ value: Double) -> Int { max(2, Int((value * fit / 2).rounded()) * 2) }
        return (even(width), even(height))
    }

    public static func isModelReady(for source: VideoSource) -> Bool {
        guard #available(macOS 26, *), let configuration = configuration(for: source) else { return false }
        return configuration.configurationModelStatus == .ready
    }

    public static func downloadModel(for source: VideoSource) throws {
        guard #available(macOS 26, *), let configuration = configuration(for: source) else {
            throw MotionWallError.upscalingUnsupported
        }
        guard configuration.configurationModelStatus != .ready else { return }
        let finished = DispatchSemaphore(value: 0)
        var failure: Error?
        configuration.downloadConfigurationModel { error in
            failure = error
            finished.signal()
        }
        finished.wait()
        if let failure { throw MotionWallError.upscalingModelUnavailable(failure.localizedDescription) }
    }

    @available(macOS 26, *)
    static func configuration(for source: VideoSource) -> VTSuperResolutionScalerConfiguration? {
        configuration(width: Int(source.size.width), height: Int(source.size.height))
    }

    @available(macOS 26, *)
    static func configuration(width: Int, height: Int) -> VTSuperResolutionScalerConfiguration? {
        guard VTSuperResolutionScalerConfiguration.isSupported else { return nil }
        return VTSuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: factor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: VTSuperResolutionScalerConfiguration.defaultRevision
        )
    }
}

protocol FrameUpscaler: AnyObject {
    func upscale(_ buffer: CVPixelBuffer, at time: CMTime) throws -> CVPixelBuffer
}

@available(macOS 26, *)
final class SuperResolutionUpscaler: FrameUpscaler {
    private let processor = VTFrameProcessor()
    private let toLinear: PixelConverter
    private let fromLinear: PixelConverter
    private let sourcePool: CVPixelBufferPool
    private let destinationPool: CVPixelBufferPool
    private let outputPool: CVPixelBufferPool
    private var previous: (source: VTFrameProcessorFrame, output: VTFrameProcessorFrame)?

    init(width: Int, height: Int) throws {
        guard let configuration = SpatialUpscale.configuration(width: width, height: height) else {
            throw MotionWallError.upscalingUnavailable(width, height)
        }
        guard configuration.configurationModelStatus == .ready else {
            throw MotionWallError.upscalingModelUnavailable("the model is not on this Mac yet")
        }
        let format = kCVPixelFormatType_64RGBAHalf
        let factor = SpatialUpscale.factor
        toLinear = try PixelConverter(toBT709TransferFunction: kCVImageBufferTransferFunction_Linear)
        fromLinear = try PixelConverter(toBT709TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2)
        sourcePool = try createPixelBufferPool(
            configuration.sourcePixelBufferAttributes, format: format, width: width, height: height)
        destinationPool = try createPixelBufferPool(
            configuration.destinationPixelBufferAttributes, format: format,
            width: width * factor, height: height * factor)
        outputPool = try createPixelBufferPool(
            [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()], format: kCVPixelFormatType_32BGRA,
            width: width * factor, height: height * factor)
        try processor.start(configuration)
    }

    deinit {
        processor.endSession()
    }

    func upscale(_ buffer: CVPixelBuffer, at time: CMTime) throws -> CVPixelBuffer {
        tagAsBT709IfUntagged(buffer)
        let source = try toLinear.convert(buffer, using: sourcePool)
        let destination = try makeBuffer(from: destinationPool)
        guard let sourceFrame = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: time),
            let destinationFrame = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: time),
            let parameters = VTSuperResolutionScalerParameters(
                sourceFrame: sourceFrame,
                previousFrame: previous?.source,
                previousOutputFrame: previous?.output,
                opticalFlow: nil,
                submissionMode: previous == nil ? .random : .sequential,
                destinationFrame: destinationFrame
            )
        else { throw MotionWallError.frameProcessingFailed("the frame at \(time.seconds)s was rejected") }
        try processor.processAndWait(parameters)
        previous = (sourceFrame, destinationFrame)
        // The scaler darkens gamma-encoded input by about 2%; it expects linear light.
        tagAsBT709IfUntagged(destination, transferFunction: kCVImageBufferTransferFunction_Linear)
        return try fromLinear.convert(destination, using: outputPool)
    }
}
