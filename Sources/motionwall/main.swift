import Foundation

func report(_ message: String) {
    print(message)
    fflush(stdout)
}

func askToOverwrite(name: String, category: String) -> Bool {
    print("A wallpaper named \"\(name)\" already exists in \"\(category)\".")
    print("Replace it? [y/N] ", terminator: "")
    fflush(stdout)
    guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
        return false
    }
    return answer == "y" || answer == "yes"
}

do {
    let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
    let source = try VideoSource(url: arguments.input)
    let width = arguments.width ?? Int(source.size.width)
    let height = arguments.height ?? Int(source.size.height)

    let library = AerialLibrary()
    try library.prepareDirectories()
    let manifest = try library.load()
    let target = try library.resolveTarget(
        name: arguments.name,
        category: arguments.category,
        in: manifest,
        confirmOverwrite: arguments.force ? { _, _ in true } : askToOverwrite
    )

    report("source:    \(Int(source.size.width))x\(Int(source.size.height)) at \(Int(source.frameRate.rounded())) fps, \(source.frameCount) frames")
    report("output:    \(width)x\(height), HEVC Main 10 with temporal layers")
    report("wallpaper: \"\(arguments.name)\" in \"\(arguments.category)\"\(target.replacingAsset ? " (replacing)" : "")")

    let staging = FileManager.default.temporaryDirectory
        .appendingPathComponent("motionwall-\(target.assetID).mov")
    var lastPercent = -1
    try WallpaperEncoder(
        source: source,
        output: staging,
        width: width,
        height: height,
        bitrate: arguments.bitrateMbps * 1_000_000
    ) { done, total in
        let percent = done * 100 / max(total, 1)
        if percent != lastPercent && percent % 10 == 0 {
            lastPercent = percent
            report("encoding: \(percent)%")
        }
    }.run()

    let videoDestination = library.videoURL(for: target.assetID)
    if FileManager.default.fileExists(atPath: videoDestination.path) {
        try FileManager.default.removeItem(at: videoDestination)
    }
    try FileManager.default.moveItem(at: staging, to: videoDestination)

    let thumbnailDestination = library.thumbnailURL(for: target.assetID)
    if FileManager.default.fileExists(atPath: thumbnailDestination.path) {
        try FileManager.default.removeItem(at: thumbnailDestination)
    }
    try ThumbnailMaker(source: source, frame: arguments.thumbnailFrame, output: thumbnailDestination)
        .run()

    try library.save(
        library.updated(
            manifest, target: target, name: arguments.name, categoryName: arguments.category))
    library.restartWallpaperAgent()

    report("")
    report("installed \(videoDestination.path)")
    report("thumbnail from frame \(arguments.thumbnailFrame)")
    report("open System Settings > Wallpaper and pick \"\(arguments.name)\" under \"\(arguments.category)\"")
} catch let error as MotionWallError {
    FileHandle.standardError.write((error.description + "\n").data(using: .utf8)!)
    exit(error.isUsage ? 2 : 1)
} catch {
    FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!)
    exit(1)
}

extension MotionWallError {
    var isUsage: Bool {
        if case .usage = self { return true }
        return false
    }
}
