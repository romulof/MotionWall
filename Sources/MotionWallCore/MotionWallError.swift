import Foundation

public enum MotionWallError: Error, CustomStringConvertible {
    case usage(String)
    case missingInput(URL)
    case noVideoTrack(URL)
    case cannotRead(URL)
    case sessionCreate(OSStatus)
    case property(String, OSStatus)
    case temporalLayersUnsupported
    case pixelBufferAllocation
    case encodeFrame(OSStatus)
    case frameInterpolationUnsupported
    case frameInterpolationUnavailable(Int, Int)
    case upscalingUnsupported
    case upscalingUnavailable(Int, Int)
    case upscalingModelUnavailable(String)
    case frameProcessingFailed(String)
    case wallpaperSelectionUnsupported
    case wallpaperSelectionFailed(String)
    case noEncodedSamples
    case writeFailed(String)
    case thumbnailFrameOutOfRange(Int, Int)
    case manifestUnreadable(URL)
    case appleCategory(String)
    case appleAsset(String, String)
    case cancelledByUser
    case concurrencyFailure

    public var description: String {
        switch self {
        case .usage(let text):
            return text
        case .missingInput(let url):
            return "input not found: \(url.path)"
        case .noVideoTrack(let url):
            return "no video track in \(url.path)"
        case .cannotRead(let url):
            return "cannot read \(url.path)"
        case .sessionCreate(let status):
            return "VTCompressionSessionCreate failed with status \(status)"
        case .property(let name, let status):
            return "cannot set encoder property \(name): status \(status)"
        case .temporalLayersUnsupported:
            return """
                this encoder cannot produce HEVC temporal layers, so the unlock ramp would fail; \
                a hardware HEVC encoder is required
                """
        case .pixelBufferAllocation:
            return "cannot allocate a pixel buffer"
        case .encodeFrame(let status):
            return "encoding a frame failed with status \(status)"
        case .frameInterpolationUnsupported:
            return "interpolating to \(FrameRateUplift.frameRate) fps needs macOS 15.4 or later and a Mac that supports VideoToolbox frame rate conversion"
        case .frameInterpolationUnavailable(let width, let height):
            return "this Mac cannot interpolate \(width)x\(height) video; the limit is 8192x4320"
        case .upscalingUnsupported:
            return "upscaling needs macOS 26 or later and a Mac that supports VideoToolbox super resolution"
        case .upscalingUnavailable(let width, let height):
            return "VideoToolbox cannot upscale \(width)x\(height) video; the limit is 1920x1080"
        case .upscalingModelUnavailable(let reason):
            return "downloading the upscaling model failed: \(reason)"
        case .frameProcessingFailed(let reason):
            return "processing frames with VideoToolbox failed: \(reason)"
        case .wallpaperSelectionUnsupported:
            return "your current wallpaper isn't an animated one, so MotionWall can't swap it; pick the new one in Wallpaper settings"
        case .wallpaperSelectionFailed(let reason):
            return "setting the wallpaper failed: \(reason)"
        case .noEncodedSamples:
            return "the encoder produced no frames"
        case .writeFailed(let reason):
            return "writing the movie failed: \(reason)"
        case .thumbnailFrameOutOfRange(let requested, let available):
            return "thumbnail frame \(requested) is outside the video, which has \(available) frames"
        case .manifestUnreadable(let url):
            return "cannot read the wallpaper manifest at \(url.path)"
        case .appleCategory(let name):
            return "\"\(name)\" is an Apple category and cannot be modified"
        case .appleAsset(let name, let category):
            return "\"\(name)\" in \"\(category)\" is an Apple wallpaper and cannot be replaced"
        case .cancelledByUser:
            return "cancelled"
        case .concurrencyFailure:
            return "an asynchronous load returned no result"
        }
    }
}
