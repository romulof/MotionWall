import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VideoDropTarget: NSViewRepresentable {
    var isEnabled: Bool
    var onHover: (URL?) -> Void
    var onDrop: (URL) -> Void

    func makeNSView(context: Context) -> VideoDropView {
        let view = VideoDropView()
        view.registerForDraggedTypes([.fileURL])
        return view
    }

    func updateNSView(_ view: VideoDropView, context: Context) {
        view.isEnabled = isEnabled
        view.onHover = onHover
        view.onDrop = onDrop
    }
}

final class VideoDropView: NSView {
    var isEnabled = true
    var onHover: (URL?) -> Void = { _ in }
    var onDrop: (URL) -> Void = { _ in }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEnabled, let url = video(in: sender) else { return [] }
        onHover(url)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isEnabled && video(in: sender) != nil ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHover(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEnabled, let url = video(in: sender) else { return false }
        onDrop(url)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onHover(nil)
    }

    private func video(in sender: NSDraggingInfo) -> URL? {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        guard let url = urls?.first,
            let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
            type.conforms(to: .movie)
        else { return nil }
        return url
    }
}
