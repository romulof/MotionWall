import AppKit
import MotionWallCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = InstallModel()
    @State private var choosingFile = false

    private let wallpaperSettings = URL(
        string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!

    var body: some View {
        Group {
            if model.source == nil || model.hovered != nil {
                editor.hidden().overlay { dropZone }
            } else {
                editor
            }
        }
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 2)
        .frame(width: 780)
        .background(WindowGlass().ignoresSafeArea())
        .toolbar { CenteredWindowTitle(title: "MotionWall") }
        .overlay(
            VideoDropTarget(
                isEnabled: !model.isBusy,
                onHover: { model.hover($0) },
                onDrop: { model.drop($0) }
            )
            .ignoresSafeArea()
        )
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
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            if let hovered = model.hovered {
                hoveredDetails(hovered)
            } else if model.phase == .loading {
                Text("Reading video…").font(.title2.weight(.semibold))
                ProgressView().controlSize(.small)
            } else {
                Text("Drop a video here").font(.title2.weight(.semibold))
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
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    model.hovered != nil ? Color.accentColor : Color.secondary.opacity(0.35),
                    style: StrokeStyle(lineWidth: model.hovered != nil ? 2.5 : 1.5, dash: [8, 6])
                )
        )
    }

    @ViewBuilder
    private func hoveredDetails(_ hovered: HoveredVideo) -> some View {
        Text(hovered.url.lastPathComponent)
            .font(.title2.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
        if let source = hovered.source {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
                detailRow("Width", "\(Int(source.size.width))")
                detailRow("Height", "\(Int(source.size.height))")
                detailRow("Frame rate", formattedFrameRate(source))
                detailRow("Bitrate", source.bitrateMbps.map { "\($0) Mbit/s" } ?? "Unknown")
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

    private func formattedFrameRate(_ source: VideoSource) -> String {
        "\(source.frameRate.formatted(.number.precision(.fractionLength(0...2)))) fps"
    }

    private var editor: some View {
        HStack(alignment: .top, spacing: 16) {
            settingsForm
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(
                    Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .disabled(model.isBusy)
            previewColumn
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var sourceRow: some View {
        if let source = model.source {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(source.url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Button("Change…") { choosingFile = true }
                    .glassButton()
                    .controlSize(.regular)
                    .disabled(model.isBusy)
            }
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
            formRow("Width") {
                TextField(
                    "Width", text: $model.width,
                    prompt: Text(verbatim: model.source.map { "\(Int($0.size.width))" } ?? "source width"))
            }
            formRow("Height") {
                TextField(
                    "Height", text: $model.height,
                    prompt: Text(verbatim: model.source.map { "\(Int($0.size.height))" } ?? "source height"))
            }
            formRow("Frame rate") {
                Text(verbatim: model.source.map { formattedFrameRate($0) } ?? "")
                .foregroundStyle(.secondary)
            }
            formRow("Bitrate") {
                HStack(spacing: 6) {
                    TextField("Bitrate", value: $model.bitrateMbps, format: .number)
                        .frame(width: 56)
                    Stepper("Bitrate", value: $model.bitrateMbps, in: 1...1000)
                        .labelsHidden()
                    Text("Mbit/s").foregroundStyle(.secondary)
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

    private var thumbnailPreview: some View {
        Group {
            if let preview = model.preview {
                Image(decorative: preview, scale: 2)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(
            width: CGFloat(ThumbnailMaker.tileWidth) / 2,
            height: CGFloat(ThumbnailMaker.tileHeight) / 2
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var previewColumn: some View {
        VStack(spacing: 12) {
            sourceRow
            thumbnailPreview
            Spacer(minLength: 0)
            status
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .done = model.phase {
                Button {
                    NSWorkspace.shared.open(wallpaperSettings)
                } label: {
                    Text("Open Wallpaper Settings").frame(maxWidth: .infinity)
                }
                .glassButton()
            }
            Button {
                model.install()
            } label: {
                Text("Install").frame(maxWidth: .infinity)
            }
            .glassButton(prominent: true)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canInstall)
        }
        .controlSize(.large)
        .frame(width: CGFloat(ThumbnailMaker.tileWidth) / 2)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .idle, .loading:
            EmptyView()
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the wallpaper library…")
            }
        case .encoding(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: fraction)
                Text("Encoding \(Int(fraction * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .finishing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…")
            }
        case .done(let url):
            VStack(alignment: .leading, spacing: 2) {
                Text("Installed \(url.path)").lineLimit(1).truncationMode(.middle)
                Text(
                    "Open System Settings > Wallpaper and pick \"\(model.name)\" under \"\(model.category)\"."
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(3)
        }
    }
}
