import CoreMedia

extension WallpaperRequest {
    public static let bitrateStepKbps = 100

    public static func suggestedBitrateKbps(for source: VideoSource, upliftsFrameRate: Bool) -> Int {
        let hevcKbps =
            source.bitsPerSecond > 0
            ? source.bitsPerSecond / 1000 * hevcEquivalence(of: source.codec)
            : Double(fallbackBitrateKbps)
        let frameCost = upliftsFrameRate ? interpolatedFrameCost(from: source.frameRate) : 1
        let steps = (hevcKbps * frameCost / Double(bitrateStepKbps)).rounded()
        return max(1, Int(steps)) * bitrateStepKbps
    }

    // Calibrated on 24 to 120 fps: doubling the bitrate kept the 24 fps quality, so an added frame costs a quarter of a source frame.
    private static func interpolatedFrameCost(from frameRate: Double) -> Double {
        let addedFramesPerSourceFrame = max(0, Double(FrameRateUplift.frameRate) / frameRate - 1)
        return 1 + addedFramesPerSourceFrame * 0.25
    }

    private static func hevcEquivalence(of codec: CMVideoCodecType) -> Double {
        switch codec {
        case kCMVideoCodecType_AV1:
            return 1.3
        case kCMVideoCodecType_H264:
            return 0.6
        case kCMVideoCodecType_MPEG4Video, kCMVideoCodecType_H263, kCMVideoCodecType_MPEG2Video,
            kCMVideoCodecType_MPEG1Video:
            return 0.4
        case kCMVideoCodecType_AppleProRes4444XQ, kCMVideoCodecType_AppleProRes4444,
            kCMVideoCodecType_AppleProRes422HQ, kCMVideoCodecType_AppleProRes422,
            kCMVideoCodecType_AppleProRes422LT, kCMVideoCodecType_AppleProRes422Proxy,
            kCMVideoCodecType_JPEG, kCMVideoCodecType_JPEG_OpenDML, kCMVideoCodecType_DVCNTSC,
            kCMVideoCodecType_DVCPAL:
            return 0.1
        default:
            return 1
        }
    }
}
