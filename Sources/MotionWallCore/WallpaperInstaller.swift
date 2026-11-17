import Foundation

public struct WallpaperRequest {
    public static let fallbackBitrateMbps = 12

    public var input: URL
    public var name: String
    public var category: String
    public var thumbnailFrame: Int
    public var width: Int?
    public var height: Int?
    public var bitrateMbps: Int?

    public init(
        input: URL,
        name: String,
        category: String = "Custom",
        thumbnailFrame: Int = 1,
        width: Int? = nil,
        height: Int? = nil,
        bitrateMbps: Int? = nil
    ) {
        self.input = input
        self.name = name
        self.category = category
        self.thumbnailFrame = thumbnailFrame
        self.width = width
        self.height = height
        self.bitrateMbps = bitrateMbps
    }
}

public struct PreparedInstall {
    public let request: WallpaperRequest
    public let source: VideoSource
    public let width: Int
    public let height: Int
    public let bitrateMbps: Int
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
            bitrateMbps: request.bitrateMbps ?? source.bitrateMbps
                ?? WallpaperRequest.fallbackBitrateMbps,
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
            bitrate: prepared.bitrateMbps * 1_000_000,
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
