import AVFoundation
import Foundation

struct VideoSource {
    let url: URL
    let track: AVAssetTrack
    let asset: AVURLAsset
    let size: CGSize
    let frameRate: Double
    let frameCount: Int

    init(url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MotionWallError.missingInput(url)
        }
        let asset = AVURLAsset(url: url)
        let tracks = try runBlocking { try await asset.loadTracks(withMediaType: .video) }
        guard let track = tracks.first else { throw MotionWallError.noVideoTrack(url) }

        let (size, nominalRate, duration) = try runBlocking {
            try await (
                track.load(.naturalSize),
                track.load(.nominalFrameRate),
                track.load(.timeRange).duration
            )
        }

        self.url = url
        self.asset = asset
        self.track = track
        self.size = size
        self.frameRate = nominalRate > 0 ? Double(nominalRate) : 24
        self.frameCount = max(Int((duration.seconds * self.frameRate).rounded()), 1)
    }
}
