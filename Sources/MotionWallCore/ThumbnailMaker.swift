import AVFoundation
import CoreImage
import Foundation

public struct ThumbnailMaker {
    public static let tileWidth = 642
    public static let tileHeight = 390

    let source: VideoSource
    let frame: Int

    public init(source: VideoSource, frame: Int) {
        self.source = source
        self.frame = frame
    }

    public func write(to output: URL) throws {
        try CIContext(options: [.cacheIntermediates: false]).writePNGRepresentation(
            of: try makeTile(),
            to: output,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
    }

    public func makeImage() throws -> CGImage {
        let tile = try makeTile()
        guard
            let image = CIContext(options: [.cacheIntermediates: false]).createCGImage(
                tile, from: tile.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        else {
            throw MotionWallError.pixelBufferAllocation
        }
        return image
    }

    private func makeTile() throws -> CIImage {
        guard frame <= source.frameCount else {
            throw MotionWallError.thumbnailFrameOutOfRange(frame, source.frameCount)
        }

        let generator = AVAssetImageGenerator(asset: source.asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let timescale = CMTimeScale(source.frameRate.rounded())
        let time = CMTime(value: CMTimeValue(frame - 1), timescale: timescale)
        let cgImage = try runBlocking {
            try await generator.image(at: time).image
        }

        let full = CIImage(cgImage: cgImage)
        let tileAspect = Double(Self.tileWidth) / Double(Self.tileHeight)
        let sourceAspect = full.extent.width / full.extent.height
        let cropWidth = sourceAspect > tileAspect ? full.extent.height * tileAspect : full.extent.width
        let cropHeight = sourceAspect > tileAspect ? full.extent.height : full.extent.width / tileAspect
        let cropped = full.cropped(
            to: CGRect(
                x: full.extent.midX - cropWidth / 2,
                y: full.extent.midY - cropHeight / 2,
                width: cropWidth,
                height: cropHeight
            )
        )

        guard let filter = CIFilter(name: "CILanczosScaleTransform") else {
            throw MotionWallError.pixelBufferAllocation
        }
        let scale = max(Double(Self.tileWidth) / cropWidth, Double(Self.tileHeight) / cropHeight)
        filter.setValue(cropped, forKey: kCIInputImageKey)
        filter.setValue(scale, forKey: kCIInputScaleKey)
        filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
        guard let scaled = filter.outputImage else { throw MotionWallError.pixelBufferAllocation }

        let centered = scaled.transformed(
            by: CGAffineTransform(
                translationX: (Double(Self.tileWidth) - scaled.extent.width) / 2 - scaled.extent.origin.x,
                y: (Double(Self.tileHeight) - scaled.extent.height) / 2 - scaled.extent.origin.y
            )
        )
        return centered.cropped(
            to: CGRect(x: 0, y: 0, width: Self.tileWidth, height: Self.tileHeight)
        )
    }
}
