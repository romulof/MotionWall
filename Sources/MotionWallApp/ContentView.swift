import AppKit
import MotionWallCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = InstallModel()
    @State private var choosingFile = false
    @Namespace private var morph

    private let windowWidth: CGFloat = 780
    private let optionValueWidth: CGFloat = 92

    private let wallpaperSettings = URL(
        string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!

    private var showsEditor: Bool { model.source != nil && model.hovered == nil }

    private var dropStage: DropStage {
        if let hovered = model.hovered {
            if hovered.source != nil { return .hovering(hovered.url, .ready) }
            return .hovering(hovered.url, hovered.unreadable ? .unreadable : .reading)
        }
        if model.phase == .loading { return .loading }
        if case .failed(let message) = model.phase { return .prompt(failure: message) }
        return .prompt(failure: nil)
    }

    private var stageAnimation: Animation {
        if showsEditor { return .spring(response: 0.55, dampingFraction: 0.82) }
        if model.source != nil { return .easeOut(duration: 0.2) }
        return .spring(response: 0.4, dampingFraction: 0.86)
    }

    var body: some View {
        editor(morphing: false)
            .hidden()
            .disabled(true)
            .accessibilityHidden(true)
            .overlay {
                if showsEditor {
                    editor(morphing: true)
                } else {
                    dropZone
                }
            }
            .animation(stageAnimation, value: showsEditor ? nil : dropStage)
            .padding([.horizontal, .bottom], 16)
            .padding(.top, 2)
            .frame(width: windowWidth)
            .background(WindowGlass().ignoresSafeArea())
            .background(
                WindowCloseGuard(
                    needsConfirmation: model.isBusy,
                    onPause: model.pauseInstall,
                    onResume: model.resumeInstall,
                    onConfirm: model.cancelInstall
                )
            )
            .toolbar { CenteredWindowTitle(title: "MotionWall") }
            .overlay(
                VideoDropTarget(
                    isEnabled: !model.isBusy,
                    onHover: { model.hover($0) },
                    onDrop: { model.drop($0) }
                )
                .ignoresSafeArea()
            )
            .onReceive(model.$phase) { phase in
                if case .done(let wallpaper) = phase { presentCompletion(wallpaper) }
            }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.movie]) { result in
                if case .success(let url) = result { model.load(url) }
            }
            .alert(
                "Replace existing wallpaper?",
                isPresented: Binding(
                    get: { model.pendingReplacement != nil },
                    set: { if !$0 { model.cancelReplacement() } }
                ),
                presenting: model.pendingReplacement
            ) { _ in
                Button("Replace", role: .destructive) { model.confirmReplacement() }
                Button("Cancel", role: .cancel) { model.cancelReplacement() }
            } message: { prepared in
                Text(
                    "A wallpaper named \"\(prepared.request.name)\" already exists in \"\(prepared.request.category)\"."
                )
            }
    }

    private var dropZone: some View {
        ZStack {
            dropZoneBorder(Color.secondary.opacity(0.35), lineWidth: 1.5)
                .overlay(
                    dropZoneBorder(Color.accentColor, lineWidth: 2.5)
                        .opacity(model.hovered != nil ? 1 : 0)
                )
                .matchedGeometryEffect(id: MorphID.frame, in: morph)
            dropZoneContent
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(dropStage)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dropZoneBorder(_ color: Color, lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: [8, 6]))
    }

    private var dropZoneContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .foregroundStyle(.secondary)
                .matchedGeometryEffect(id: MorphID.icon, in: morph)
                .frame(width: 64, height: 50)
            if let hovered = model.hovered {
                hoveredDetails(hovered)
            } else if model.phase == .loading {
                Text("Reading video…")
                    .font(.title2.weight(.semibold))
                    .matchedGeometryEffect(id: MorphID.name, in: morph, properties: .position)
                ProgressView().controlSize(.small)
            } else {
                Text("Drop a video here")
                    .font(.title2.weight(.semibold))
                    .matchedGeometryEffect(id: MorphID.name, in: morph, properties: .position)
                Text("Any format QuickTime can read").foregroundStyle(.secondary)
                Button("Choose video…") { choosingFile = true }
                    .glassButton()
                    .controlSize(.large)
                    .padding(.top, 8)
                if case .failed(let message) = model.phase {
                    Text(message)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func hoveredDetails(_ hovered: HoveredVideo) -> some View {
        Text(hovered.url.lastPathComponent)
            .font(.title2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .matchedGeometryEffect(id: MorphID.name, in: morph, properties: .position)
        if let source = hovered.source {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                detailRow("Resolution", formattedResolution(Int(source.size.width), Int(source.size.height)))
                detailRow("Frame rate", formattedFrameRate(source))
                detailRow("Bitrate", source.bitrateKbps.map { "\($0) kbit/s" } ?? "Unknown")
            }
            Text("Release to load").foregroundStyle(.secondary).padding(.top, 4)
        } else if hovered.unreadable {
            Text("This file can't be read").foregroundStyle(.red)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(verbatim: value).monospacedDigit()
        }
    }

    private func formattedResolution(_ width: Int, _ height: Int) -> String {
        "\(width) × \(height)"
    }

    private func resolutionSummary(_ source: VideoSource) -> String {
        let original = formattedResolution(Int(source.size.width), Int(source.size.height))
        let reduced = SpatialUpscale.outputSize(for: source, upscales: false)
        guard reduced.width != Int(source.size.width) || reduced.height != Int(source.size.height) else {
            return original
        }
        return "\(original) → \(formattedResolution(reduced.width, reduced.height))"
    }

    private func formattedFrameRate(_ source: VideoSource) -> String {
        "\(source.frameRate.formatted(.number.precision(.fractionLength(0...2)))) fps"
    }

    private func editor(morphing: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                settingsForm.disabled(model.isBusy)
                Spacer(minLength: 0)
                actionArea
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .slideIn(fromLeading: windowWidth)
            previewColumn(morphing: morphing)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sourceRow(morphing: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .morph(MorphID.icon, in: morph, enabled: morphing)
                .frame(width: 26, height: 20)
            Text(verbatim: model.source?.url.lastPathComponent ?? " ")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .morph(MorphID.name, in: morph, properties: .position, enabled: morphing)
            Spacer(minLength: 8)
            Button("Change…") { choosingFile = true }
                .glassButton()
                .controlSize(.regular)
                .disabled(model.isBusy)
        }
    }

    private var settingsForm: some View {
        let frameCount = model.source?.frameCount ?? 1
        return VStack(spacing: 12) {
            formRow("Name") {
                TextField("Name", text: $model.name, prompt: Text("Required"))
            }
            formRow("Category") {
                TextField("Category", text: $model.category, prompt: Text("Required"))
            }
            formRow("Resolution") {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(verbatim: model.source.map { resolutionSummary($0) } ?? "")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: optionValueWidth, alignment: .leading)
                    if let source = model.source, model.offersUpscale {
                        let upscaled = SpatialUpscale.outputSize(for: source, upscales: true)
                        Toggle("Upscale to \(formattedResolution(upscaled.width, upscaled.height))", isOn: $model.upscales)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            formRow("Frame rate") {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(verbatim: model.source.map { formattedFrameRate($0) } ?? "")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: optionValueWidth, alignment: .leading)
                    if model.offersFrameRateUplift {
                        Toggle("Interpolate to \(FrameRateUplift.frameRate) fps", isOn: $model.upliftsFrameRate)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            formRow("Bitrate") {
                HStack(spacing: 6) {
                    TextField("Bitrate", value: $model.bitrateKbps, format: .number.grouping(.never))
                        .frame(width: 80)
                    Stepper(
                        "Bitrate", value: $model.bitrateKbps,
                        in: WallpaperRequest.bitrateStepKbps...1_000_000,
                        step: WallpaperRequest.bitrateStepKbps
                    )
                    .labelsHidden()
                    Text("kbit/s").foregroundStyle(.secondary)
                }
            }
            formRow("Thumbnail", alignment: .center) {
                HStack(spacing: 6) {
                    Slider(
                        value: Binding(
                            get: { Double(model.thumbnailFrame) },
                            set: { model.thumbnailFrame = Int($0.rounded()) }
                        ),
                        in: 1...Double(max(frameCount, 2))
                    )
                    .labelsHidden()
                    .disabled(frameCount < 2)
                    Stepper("Frame", value: $model.thumbnailFrame, in: 1...max(frameCount, 1))
                        .labelsHidden()
                }
            }
            formRow("") {
                Text("Frame \(model.thumbnailFrame) of \(frameCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, -8)
        }
        .textFieldStyle(.roundedBorder)
    }

    private func formRow<Control: View>(
        _ label: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: alignment, spacing: 10) {
            Text(label).frame(width: 76, alignment: .trailing)
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func thumbnailPreview(morphing: Bool) -> some View {
        Group {
            if let preview = model.preview {
                Image(decorative: preview, scale: 2)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .morph(MorphID.frame, in: morph, enabled: morphing)
        .frame(
            width: CGFloat(ThumbnailMaker.tileWidth) / 2,
            height: CGFloat(ThumbnailMaker.tileHeight) / 2
        )
    }

    private func previewColumn(morphing: Bool) -> some View {
        VStack(spacing: 12) {
            sourceRow(morphing: morphing)
            thumbnailPreview(morphing: morphing)
            Spacer(minLength: 0)
        }
        .controlSize(.large)
        .frame(width: CGFloat(ThumbnailMaker.tileWidth) / 2)
        .frame(maxHeight: .infinity)
    }

    private var appWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible)
    }

    private func presentCompletion(_ wallpaper: InstalledWallpaper) {
        guard let window = appWindow, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "“\(wallpaper.name)” is installed"
        alert.informativeText = "It's in System Settings › Wallpaper, under “\(wallpaper.category)”."
        alert.addButton(withTitle: "Use as Wallpaper")
        alert.addButton(withTitle: "Open Wallpaper Settings")
        alert.addButton(withTitle: "Done").keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn:
                Task {
                    if let failure = await model.useAsWallpaper(wallpaper) { presentSelectionFailure(failure) }
                }
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(wallpaperSettings)
            default:
                break
            }
        }
    }

    private func presentSelectionFailure(_ failure: String) {
        guard let window = appWindow, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Couldn't set the wallpaper"
        alert.informativeText = failure.prefix(1).uppercased() + failure.dropFirst() + "."
        alert.addButton(withTitle: "Open Wallpaper Settings")
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(wallpaperSettings) }
        }
    }

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .failed(let message) = model.phase {
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ZStack {
                if model.isBusy {
                    progress.transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Button {
                        model.install()
                    } label: {
                        Text("Install").frame(maxWidth: .infinity)
                    }
                    .glassButton(prominent: true)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canInstall)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(height: 40)
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: model.isBusy)
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if case .encoding(let fraction, _) = model.phase {
                    ProgressView(value: fraction)
                    Button {
                        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
                        confirmStop(
                            in: window, title: "Stop the install?", stopTitle: "Stop the Install",
                            pause: model.pauseInstall, resume: model.resumeInstall, stop: model.cancelInstall)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop encoding")
                    .accessibilityLabel("Stop encoding")
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            Text(progressLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var progressLabel: String {
        switch model.phase {
        case .preparing:
            return "Checking the wallpaper library…"
        case .downloadingModel:
            return "Downloading the upscaling model…"
        case .encoding(let fraction, let remaining):
            let percent = "Encoding \(Int(fraction * 100))%"
            if model.isPaused { return "\(percent) · paused" }
            guard let remaining else { return percent }
            return "\(percent) · \(formattedRemaining(remaining))"
        case .finishing:
            return "Installing…"
        case .idle, .loading, .done, .failed:
            return ""
        }
    }

    private func formattedRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        guard total >= 60 else { return "\(total)s remaining" }
        return String(format: "%d:%02d remaining", total / 60, total % 60)
    }
}

private enum DropStage: Hashable {
    enum Readiness: Hashable {
        case reading
        case ready
        case unreadable
    }

    case prompt(failure: String?)
    case loading
    case hovering(URL, Readiness)
}

private struct SlideIn: ViewModifier {
    let distance: CGFloat
    @State private var isRevealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(x: isRevealed || reduceMotion ? 0 : -distance)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { isRevealed = true }
            }
    }
}

private enum MorphID {
    static let frame = "frame"
    static let icon = "icon"
    static let name = "name"
}

extension View {
    fileprivate func slideIn(fromLeading distance: CGFloat) -> some View {
        modifier(SlideIn(distance: distance))
    }

    @ViewBuilder
    fileprivate func morph(
        _ id: String,
        in namespace: Namespace.ID,
        properties: MatchedGeometryProperties = .frame,
        enabled: Bool
    ) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace, properties: properties)
        } else {
            self
        }
    }
}
