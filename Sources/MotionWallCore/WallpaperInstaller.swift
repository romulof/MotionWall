import Foundation

public struct WallpaperRequest {
    public static let fallbackBitrateKbps = 12_000

    public var input: URL
    public var name: String
    public var category: String
    public var thumbnailFrame: Int
    public var width: Int?
    public var height: Int?
    public var bitrateKbps: Int?
    public var upliftsFrameRate: Bool

    public init(
        input: URL,
        name: String,
        category: String = "Custom",
        thumbnailFrame: Int = 1,
        width: Int? = nil,
        height: Int? = nil,
        bitrateKbps: Int? = nil,
        upliftsFrameRate: Bool = false
    ) {
        self.input = input
        self.name = name
        self.category = category
        self.thumbnailFrame = thumbnailFrame
        self.width = width
        self.height = height
        self.bitrateKbps = bitrateKbps
        self.upliftsFrameRate = upliftsFrameRate
    }
}

public struct PreparedInstall {
    public let request: WallpaperRequest
    public let source: VideoSource
    public let width: Int
    public let height: Int
    public let bitrateKbps: Int
    public let upliftsFrameRate: Bool
    let manifest: JSONObject
    let target: InstallTarget

    public var replacingAsset: Bool { target.replacingAsset }
}

public struct WallpaperInstaller {
    private let library = AerialLibrary()

    public init() {}

    public func prepare(
        _ request: WallpaperRequest,
        source: VideoSource? = nil,
        confirmOverwrite: (String, String) -> Bool
    ) throws -> PreparedInstall {
        let source = try source ?? VideoSource(url: request.input)
        let upliftsFrameRate = request.upliftsFrameRate && FrameRateUplift.applies(to: source)
        if upliftsFrameRate && !FrameRateUplift.isSupported {
            throw MotionWallError.frameInterpolationUnsupported
        }
        try library.prepareDirectories()
        let manifest = try library.load()
        let target = try library.resolveTarget(
            name: request.name,
            category: request.category,
            in: manifest,
            confirmOverwrite: confirmOverwrite
        )
        return PreparedInstall(
            request: request,
            source: source,
            width: request.width ?? Int(source.size.width),
            height: request.height ?? Int(source.size.height),
            bitrateKbps: request.bitrateKbps
                ?? WallpaperRequest.suggestedBitrateKbps(for: source, upliftsFrameRate: upliftsFrameRate),
            upliftsFrameRate: upliftsFrameRate,
            manifest: manifest,
            target: target
        )
    }

    public func install(
        _ prepared: PreparedInstall,
        onProgress: @escaping (Int, Int) -> Void
    ) throws -> URL {
        let request = prepared.request
        let target = prepared.target

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("motionwall-\(target.assetID).mov")
        try WallpaperEncoder(
            source: prepared.source,
            output: staging,
            width: prepared.width,
            height: prepared.height,
            bitrate: prepared.bitrateKbps * 1000,
            upliftsFrameRate: prepared.upliftsFrameRate,
            onProgress: onProgress
        ).run()

        let videoDestination = library.videoURL(for: target.assetID)
        if FileManager.default.fileExists(atPath: videoDestination.path) {
            try FileManager.default.removeItem(at: videoDestination)
        }
        try FileManager.default.moveItem(at: staging, to: videoDestination)

        let thumbnailDestination = library.thumbnailURL(for: target.assetID)
        if FileManager.default.fileExists(atPath: thumbnailDestination.path) {
            try FileManager.default.removeItem(at: thumbnailDestination)
        }
        try ThumbnailMaker(source: prepared.source, frame: request.thumbnailFrame)
            .write(to: thumbnailDestination)

        try library.save(
            library.updated(
                prepared.manifest, target: target, name: request.name,
                categoryName: request.category))
        library.restartWallpaperAgent()

        return videoDestination
    }
}
