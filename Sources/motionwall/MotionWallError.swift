import Foundation

enum MotionWallError: Error, CustomStringConvertible {
    case usage(String)
    case missingInput(URL)
    case noVideoTrack(URL)
    case cannotRead(URL)
    case sessionCreate(OSStatus)
    case property(String, OSStatus)
    case temporalLayersUnsupported
    case pixelBufferAllocation
    case encodeFrame(OSStatus)
    case noEncodedSamples
    case writeFailed(String)
    case thumbnailFrameOutOfRange(Int, Int)
    case manifestUnreadable(URL)
    case appleCategory(String)
    case appleAsset(String, String)
    case cancelledByUser
    case concurrencyFailure

    var description: String {
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
