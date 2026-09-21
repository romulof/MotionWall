import AVFoundation
import CoreImage
import Foundation
import VideoToolbox

private final class EncodedSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [CMSampleBuffer] = []

    func append(_ buffer: CMSampleBuffer) {
        lock.lock()
        buffers.append(buffer)
        lock.unlock()
    }

    var ordered: [CMSampleBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
    }
}

struct WallpaperEncoder {
    let source: VideoSource
    let output: URL
    let width: Int
    let height: Int
    let bitrate: Int
    let onProgress: (Int, Int) -> Void

    func run() throws {
        guard let reader = try? AVAssetReader(asset: source.asset) else {
            throw MotionWallError.cannotRead(source.url)
        }
        let readerOutput = AVAssetReaderTrackOutput(
            track: source.track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)
        guard reader.startReading() else { throw MotionWallError.cannotRead(source.url) }

        let compressor = try makeCompressor()
        let pixelBufferPool = try makePixelBufferPool()
        let ciContext = CIContext(options: [.cacheIntermediates: false])
        let colorSpace = CGColorSpace(name: CGColorSpace.itur_709)!
        let verticalScale = Double(height) / Double(source.size.height)
        let aspectCorrection =
            (Double(width) / Double(height))
            / (Double(source.size.width) / Double(source.size.height))
        let collected = EncodedSamples()
        var submitted = 0

        while let sample = readerOutput.copyNextSampleBuffer() {
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
                throw MotionWallError.pixelBufferAllocation
            }
            filter.setValue(CIImage(cvPixelBuffer: sourceBuffer), forKey: kCIInputImageKey)
            filter.setValue(verticalScale, forKey: kCIInputScaleKey)
            filter.setValue(aspectCorrection, forKey: kCIInputAspectRatioKey)
            guard let scaled = filter.outputImage else {
                throw MotionWallError.pixelBufferAllocation
            }

            var destination: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &destination)
            guard let target = destination else { throw MotionWallError.pixelBufferAllocation }
            ciContext.render(
                scaled,
                to: target,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: colorSpace
            )

            let status = VTCompressionSessionEncodeFrame(
                compressor,
                imageBuffer: target,
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
                duration: CMSampleBufferGetDuration(sample),
                frameProperties: nil,
                infoFlagsOut: nil
            ) { status, _, encoded in
                guard status == noErr, let encoded else { return }
                collected.append(encoded)
            }
            guard status == noErr else { throw MotionWallError.encodeFrame(status) }

            submitted += 1
            onProgress(submitted, source.frameCount)
        }

        VTCompressionSessionCompleteFrames(compressor, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(compressor)

        try write(samples: collected.ordered)
    }

    private func makeCompressor() throws -> VTCompressionSession {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [
                kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
            ] as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        guard status == noErr, let compressor = session else {
            throw MotionWallError.sessionCreate(status)
        }

        func set(_ key: CFString, _ value: CFTypeRef) throws {
            let status = VTSessionSetProperty(compressor, key: key, value: value)
            guard status == noErr else { throw MotionWallError.property(key as String, status) }
        }

        let keyFrameInterval = Int(source.frameRate.rounded())
        try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel)
        try set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, keyFrameInterval as CFNumber)
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, source.frameRate as CFNumber)
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_AllowTemporalCompression, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanFalse)
        try set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        try set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        try set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)

        let layersEnabled =
            VTSessionSetProperty(
                compressor, key: Self.numberOfTemporalLayers, value: 2 as CFNumber) == noErr
        guard layersEnabled else { throw MotionWallError.temporalLayersUnsupported }
        VTSessionSetProperty(compressor, key: Self.temporalIDNestingFlag, value: kCFBooleanTrue)
        VTSessionSetProperty(
            compressor, key: Self.baseLayerFrameRate, value: source.frameRate / 2 as CFNumber)

        return compressor
    }

    private static let numberOfTemporalLayers = "NumberOfTemporalLayers" as CFString
    private static let temporalIDNestingFlag = "TemporalIDNestingFlag" as CFString
    private static let baseLayerFrameRate = "BaseLayerFrameRate" as CFString

    private func makePixelBufferPool() throws -> CVPixelBufferPool {
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ] as CFDictionary,
            &pool
        )
        guard let pixelBufferPool = pool else { throw MotionWallError.pixelBufferAllocation }
        return pixelBufferPool
    }

    private func write(samples: [CMSampleBuffer]) throws {
        guard let formatDescription = samples.first.flatMap(CMSampleBufferGetFormatDescription) else {
            throw MotionWallError.noEncodedSamples
        }
        if FileManager.default.fileExists(atPath: output.path) {
            try? FileManager.default.removeItem(at: output)
        }
        guard let writer = try? AVAssetWriter(outputURL: output, fileType: .mov) else {
            throw MotionWallError.writeFailed("cannot create \(output.path)")
        }
        writer.movieTimeScale = 600

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: nil,
            sourceFormatHint: formatDescription
        )
        input.expectsMediaDataInRealTime = false
        input.mediaTimeScale = CMTimeScale(Int(source.frameRate.rounded()) * 1000)
        writer.add(input)

        guard writer.startWriting() else {
            throw MotionWallError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
        writer.startSession(atSourceTime: .zero)

        for sample in samples {
            while !input.isReadyForMoreMediaData {
                usleep(2000)
            }
            guard input.append(sample) else {
                throw MotionWallError.writeFailed(writer.error?.localizedDescription ?? "unknown")
            }
        }
        input.markAsFinished()

        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()

        guard writer.status == .completed else {
            throw MotionWallError.writeFailed(writer.error?.localizedDescription ?? "unknown")
        }
    }
}
