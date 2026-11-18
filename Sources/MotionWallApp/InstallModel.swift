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
        case encoding(Double)
        case finishing
        case done(URL)
        case failed(String)
    }

    @Published private(set) var source: VideoSource?
    @Published private(set) var preview: CGImage?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var pendingReplacement: PreparedInstall?
    @Published private(set) var hovered: HoveredVideo?
    @Published var name = ""
    @Published var category = "Custom"
    @Published var width = ""
    @Published var height = ""
    @Published var bitrateKbps = WallpaperRequest.fallbackBitrateKbps
    @Published var upliftsFrameRate = true {
        didSet {
            guard bitrateKbps == suggestedBitrateKbps(uplifting: oldValue) else { return }
            bitrateKbps = suggestedBitrateKbps(uplifting: upliftsFrameRate)
        }
    }
    @Published var thumbnailFrame = 1 {
        didSet { refreshPreview() }
    }

    private var previewTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .loading, .preparing, .encoding, .finishing: return true
        case .idle, .done, .failed: return false
        }
    }

    var canInstall: Bool { !isBusy && request != nil }

    var offersFrameRateUplift: Bool {
        guard let source else { return false }
        return FrameRateUplift.isSupported && FrameRateUplift.applies(to: source)
    }

    var request: WallpaperRequest? {
        guard let source else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedCategory.isEmpty, bitrateKbps >= WallpaperRequest.bitrateStepKbps,
            (1...source.frameCount).contains(thumbnailFrame),
            isValidDimension(width), isValidDimension(height)
        else { return nil }
        return WallpaperRequest(
            input: source.url,
            name: trimmedName,
            category: trimmedCategory,
            thumbnailFrame: thumbnailFrame,
            width: Int(width.trimmingCharacters(in: .whitespaces)),
            height: Int(height.trimmingCharacters(in: .whitespaces)),
            bitrateKbps: bitrateKbps,
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
        bitrateKbps = suggestedBitrateKbps(uplifting: upliftsFrameRate)
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

    func cancelReplacement() {
        pendingReplacement = nil
    }

    private func run(_ prepared: PreparedInstall) {
        phase = .encoding(0)
        Task {
            do {
                var lastPercent = -1
                let installed = try await onBackgroundQueue {
                    try WallpaperInstaller().install(prepared) { done, total in
                        let percent = done * 100 / max(total, 1)
                        guard percent != lastPercent else { return }
                        lastPercent = percent
                        Task { @MainActor in
                            guard case .encoding = self.phase else { return }
                            self.phase = percent >= 100 ? .finishing : .encoding(Double(percent) / 100)
                        }
                    }
                }
                phase = .done(installed)
            } catch {
                phase = .failed(message(for: error))
            }
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

    private func suggestedBitrateKbps(uplifting: Bool) -> Int {
        guard let source else { return WallpaperRequest.fallbackBitrateKbps }
        return WallpaperRequest.suggestedBitrateKbps(
            for: source, upliftsFrameRate: uplifting && offersFrameRateUplift)
    }

    private func isValidDimension(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || (Int(trimmed) ?? 0) >= 1
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
