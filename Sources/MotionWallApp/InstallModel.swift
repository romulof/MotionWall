import CoreGraphics
import Foundation
import MotionWallCore

struct HoveredVideo {
    let url: URL
    var source: VideoSource?
    var unreadable = false
}

@MainActor
final class InstallModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case preparing
        case downloadingModel
        case encoding(Double, remaining: TimeInterval?)
        case finishing
        case done(InstalledWallpaper)
        case failed(String)
    }

    @Published private(set) var source: VideoSource?
    @Published private(set) var preview: CGImage?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pendingReplacement: PreparedInstall?
    @Published private(set) var hovered: HoveredVideo?
    @Published var name = ""
    @Published var category = "Custom"
    @Published var bitrateKbps = WallpaperRequest.fallbackBitrateKbps
    @Published var upscales = true {
        didSet {
            guard bitrateKbps == suggestedBitrateKbps(upscaling: oldValue, uplifting: upliftsFrameRate) else { return }
            bitrateKbps = suggestedBitrateKbps(upscaling: upscales, uplifting: upliftsFrameRate)
        }
    }
    @Published var upliftsFrameRate = true {
        didSet {
            guard bitrateKbps == suggestedBitrateKbps(upscaling: upscales, uplifting: oldValue) else { return }
            bitrateKbps = suggestedBitrateKbps(upscaling: upscales, uplifting: upliftsFrameRate)
        }
    }
    @Published var thumbnailFrame = 1 {
        didSet { refreshPreview() }
    }

    @Published private(set) var isPaused = false
    private var control: InstallControl?
    private var previewTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .loading, .preparing, .downloadingModel, .encoding, .finishing: return true
        case .idle, .done, .failed: return false
        }
    }

    var canInstall: Bool { !isBusy && request != nil }

    var offersUpscale: Bool {
        guard let source else { return false }
        return SpatialUpscale.isSupported && SpatialUpscale.applies(to: source)
    }

    var outputSize: (width: Int, height: Int)? {
        source.map { SpatialUpscale.outputSize(for: $0, upscales: upscales && offersUpscale) }
    }

    var offersFrameRateUplift: Bool {
        guard let source else { return false }
        return FrameRateUplift.isSupported && FrameRateUplift.applies(to: source)
    }

    var request: WallpaperRequest? {
        guard let source, let outputSize else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedCategory.isEmpty, bitrateKbps >= WallpaperRequest.bitrateStepKbps,
            (1...source.frameCount).contains(thumbnailFrame)
        else { return nil }
        return WallpaperRequest(
            input: source.url,
            name: trimmedName,
            category: trimmedCategory,
            thumbnailFrame: thumbnailFrame,
            width: outputSize.width,
            height: outputSize.height,
            bitrateKbps: bitrateKbps,
            upscales: upscales && offersUpscale,
            upliftsFrameRate: upliftsFrameRate && offersFrameRateUplift
        )
    }

    func load(_ url: URL) {
        previewTask?.cancel()
        source = nil
        preview = nil
        phase = .loading
        Task {
            do {
                adopt(try await onBackgroundQueue { try VideoSource(url: url) })
            } catch {
                phase = .failed(message(for: error))
            }
        }
    }

    func hover(_ url: URL?) {
        guard url != hovered?.url else { return }
        hoverTask?.cancel()
        guard let url else {
            hovered = nil
            return
        }
        hovered = HoveredVideo(url: url)
        hoverTask = Task {
            let source = try? await onBackgroundQueue { try VideoSource(url: url) }
            guard !Task.isCancelled, hovered?.url == url else { return }
            hovered?.source = source
            hovered?.unreadable = source == nil
        }
    }

    func drop(_ url: URL) {
        hoverTask?.cancel()
        let preloaded = hovered?.url == url ? hovered?.source : nil
        hovered = nil
        if let preloaded {
            previewTask?.cancel()
            adopt(preloaded)
        } else {
            load(url)
        }
    }

    private func adopt(_ loaded: VideoSource) {
        source = loaded
        if name.isEmpty {
            name = loaded.url.deletingPathExtension().lastPathComponent
        }
        thumbnailFrame = 1
        bitrateKbps = suggestedBitrateKbps(upscaling: upscales, uplifting: upliftsFrameRate)
        phase = .idle
    }

    func install() {
        guard let request, let source else { return }
        phase = .preparing
        Task {
            do {
                let prepared = try await onBackgroundQueue {
                    try WallpaperInstaller().prepare(request, source: source) { _, _ in true }
                }
                if prepared.replacingAsset {
                    pendingReplacement = prepared
                    phase = .idle
                } else {
                    run(prepared)
                }
            } catch {
                phase = .failed(message(for: error))
            }
        }
    }

    func confirmReplacement() {
        guard let prepared = pendingReplacement else { return }
        pendingReplacement = nil
        run(prepared)
    }

    func pauseInstall() {
        control?.pause()
        isPaused = control != nil
    }

    func resumeInstall() {
        control?.resume()
        isPaused = false
    }

    func cancelInstall() {
        control?.cancel()
        isPaused = false
    }

    func useAsWallpaper(_ wallpaper: InstalledWallpaper) async -> String? {
        do {
            try await onBackgroundQueue { try WallpaperSelection.select(assetID: wallpaper.assetID) }
            return nil
        } catch {
            return message(for: error)
        }
    }

    func cancelReplacement() {
        pendingReplacement = nil
    }

    private func run(_ prepared: PreparedInstall) {
        phase = .preparing
        let control = InstallControl()
        self.control = control
        Task {
            do {
                let needsModel = try await onBackgroundQueue {
                    prepared.upscales && !SpatialUpscale.isModelReady(for: prepared.source)
                }
                phase = needsModel ? .downloadingModel : .encoding(0, remaining: nil)
                var started: Date?
                var lastPermille = -1
                _ = try await onBackgroundQueue {
                    try WallpaperInstaller().install(prepared, isCancelled: control.waitWhilePausedThenIsCancelled) { done, total in
                        let permille = done * 1000 / max(total, 1)
                        guard permille != lastPermille else { return }
                        lastPermille = permille
                        let now = Date()
                        let start = started ?? now
                        started = start
                        let fraction = Double(permille) / 1000
                        let elapsed = now.timeIntervalSince(start) - control.pausedDuration
                        let remaining = fraction >= 0.02 && elapsed >= 3 ? elapsed * (1 - fraction) / fraction : nil
                        Task { @MainActor in
                            switch self.phase {
                            case .downloadingModel, .encoding: break
                            default: return
                            }
                            self.phase = permille >= 1000 ? .finishing : .encoding(fraction, remaining: remaining)
                        }
                    }
                }
                phase = .done(
                    InstalledWallpaper(
                        assetID: prepared.assetID, name: prepared.request.name, category: prepared.request.category))
            } catch MotionWallError.cancelledByUser {
                phase = .idle
            } catch {
                phase = .failed(message(for: error))
            }
            self.control = nil
            isPaused = false
        }
    }

    private func refreshPreview() {
        previewTask?.cancel()
        guard let source, (1...source.frameCount).contains(thumbnailFrame) else {
            preview = nil
            return
        }
        let frame = thumbnailFrame
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let image = try? await onBackgroundQueue {
                try ThumbnailMaker(source: source, frame: frame).makeImage()
            }
            guard !Task.isCancelled else { return }
            preview = image
        }
    }

    private func suggestedBitrateKbps(upscaling: Bool, uplifting: Bool) -> Int {
        guard let source else { return WallpaperRequest.fallbackBitrateKbps }
        let size = SpatialUpscale.outputSize(for: source, upscales: upscaling && offersUpscale)
        return WallpaperRequest.suggestedBitrateKbps(
            for: source, width: size.width, height: size.height,
            upliftsFrameRate: uplifting && offersFrameRateUplift)
    }

    private func message(for error: Error) -> String {
        (error as? MotionWallError)?.description ?? error.localizedDescription
    }
}

// MotionWallCore blocks on semaphores, so its work must stay off the main actor and the cooperative pool.
private func onBackgroundQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

private final class InstallControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false
    private var pausedSince: Date?
    private var pausedTotal: TimeInterval = 0

    func pause() {
        condition.lock()
        if pausedSince == nil { pausedSince = Date() }
        condition.unlock()
    }

    func resume() {
        condition.lock()
        if let since = pausedSince {
            pausedTotal += Date().timeIntervalSince(since)
            pausedSince = nil
        }
        condition.broadcast()
        condition.unlock()
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.unlock()
        resume()
    }

    func waitWhilePausedThenIsCancelled() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        while pausedSince != nil && !cancelled { condition.wait() }
        return cancelled
    }

    var pausedDuration: TimeInterval {
        condition.lock()
        defer { condition.unlock() }
        return pausedTotal + (pausedSince.map { Date().timeIntervalSince($0) } ?? 0)
    }
}

struct InstalledWallpaper: Equatable {
    let assetID: String
    let name: String
    let category: String
}
