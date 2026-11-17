import AVFoundation
import Foundation

public struct VideoSource {
    public let url: URL
    let track: AVAssetTrack
    let asset: AVURLAsset
    public let size: CGSize
    public let frameRate: Double
    public let frameCount: Int
    public let bitsPerSecond: Double

    public var bitrateMbps: Int? {
        bitsPerSecond > 0 ? max(1, Int((bitsPerSecond / 1_000_000).rounded())) : nil
    }

    public init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MotionWallError.missingInput(url)
        }
        let asset = AVURLAsset(url: url)
        let tracks = try runBlocking { try await asset.loadTracks(withMediaType: .video) }
        guard let track = tracks.first else { throw MotionWallError.noVideoTrack(url) }

        let (size, nominalRate, duration, dataRate) = try runBlocking {
            try await (
                track.load(.naturalSize),
                track.load(.nominalFrameRate),
                track.load(.timeRange).duration,
                track.load(.estimatedDataRate)
            )
        }

        self.url = url
        self.asset = asset
        self.track = track
        self.size = size
        self.frameRate = nominalRate > 0 ? Double(nominalRate) : 24
        self.frameCount = max(Int((duration.seconds * self.frameRate).rounded()), 1)
        self.bitsPerSecond = Double(dataRate)
    }
}
