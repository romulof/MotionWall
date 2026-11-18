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
    public var upscales: Bool
    public var upliftsFrameRate: Bool

    public init(
        input: URL,
        name: String,
        category: String = "Custom",
        thumbnailFrame: Int = 1,
        width: Int? = nil,
        height: Int? = nil,
        bitrateKbps: Int? = nil,
        upscales: Bool = false,
        upliftsFrameRate: Bool = false
    ) {
        self.input = input
        self.name = name
        self.category = category
        self.thumbnailFrame = thumbnailFrame
        self.width = width
        self.height = height
        self.bitrateKbps = bitrateKbps
        self.upscales = upscales
        self.upliftsFrameRate = upliftsFrameRate
    }
}

public struct PreparedInstall {
    public let request: WallpaperRequest
    public let source: VideoSource
    public let width: Int
    public let height: Int
    public let bitrateKbps: Int
    public let upscales: Bool
    public let upliftsFrameRate: Bool
    let manifest: JSONObject
    let target: InstallTarget

    public var replacingAsset: Bool { target.replacingAsset }
    public var assetID: String { target.assetID }
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
        let defaultSize = SpatialUpscale.outputSize(for: source, upscales: request.upscales)
        let width = request.width ?? (request.upscales ? defaultSize.width : Int(source.size.width))
        let height = request.height ?? (request.upscales ? defaultSize.height : Int(source.size.height))
        let upscales =
            request.upscales && (width > Int(source.size.width) || height > Int(source.size.height))
        if upscales && !SpatialUpscale.isSupported {
            throw MotionWallError.upscalingUnsupported
        }
        if upscales && !SpatialUpscale.applies(to: source) {
            throw MotionWallError.upscalingUnavailable(Int(source.size.width), Int(source.size.height))
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
            width: width,
            height: height,
            bitrateKbps: request.bitrateKbps
                ?? WallpaperRequest.suggestedBitrateKbps(
                    for: source, width: width, height: height, upliftsFrameRate: upliftsFrameRate),
            upscales: upscales,
            upliftsFrameRate: upliftsFrameRate,
            manifest: manifest,
            target: target
        )
    }

    public func install(
        _ prepared: PreparedInstall,
        isCancelled: @escaping () -> Bool = { false },
        onProgress: @escaping (Int, Int) -> Void
    ) throws -> URL {
        let request = prepared.request
        let target = prepared.target

        if prepared.upscales {
            try SpatialUpscale.downloadModel(for: prepared.source)
        }
        if isCancelled() { throw MotionWallError.cancelledByUser }

        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("motionwall-\(target.assetID).mov")
        try WallpaperEncoder(
            source: prepared.source,
            output: staging,
            width: prepared.width,
            height: prepared.height,
            bitrate: prepared.bitrateKbps * 1000,
            upscales: prepared.upscales,
            upliftsFrameRate: prepared.upliftsFrameRate,
            isCancelled: isCancelled,
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
