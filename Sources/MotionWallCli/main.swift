import Foundation
import MotionWallCore

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
    let request = WallpaperRequest(
        input: arguments.input,
        name: arguments.name,
        category: arguments.category,
        thumbnailFrame: arguments.thumbnailFrame,
        width: arguments.width,
        height: arguments.height,
        bitrateKbps: arguments.bitrateKbps
    )
    let installer = WallpaperInstaller()
    let prepared = try installer.prepare(
        request,
        confirmOverwrite: arguments.force ? { _, _ in true } : askToOverwrite
    )
    let source = prepared.source

    report("source:    \(Int(source.size.width))x\(Int(source.size.height)) at \(Int(source.frameRate.rounded())) fps, \(source.frameCount) frames")
    report("output:    \(prepared.width)x\(prepared.height) at \(prepared.bitrateKbps) kbit/s, HEVC Main 10 with temporal layers")
    report("wallpaper: \"\(arguments.name)\" in \"\(arguments.category)\"\(prepared.replacingAsset ? " (replacing)" : "")")

    var lastPercent = -1
    let videoDestination = try installer.install(prepared) { done, total in
        let percent = done * 100 / max(total, 1)
        if percent != lastPercent && percent % 10 == 0 {
            lastPercent = percent
            report("encoding: \(percent)%")
        }
    }

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
