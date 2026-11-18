import AppKit
import SwiftUI

func confirmStop(
    in window: NSWindow,
    title: String,
    stopTitle: String,
    pause: () -> Void,
    resume: @escaping () -> Void,
    stop: @escaping () -> Void
) {
    guard window.attachedSheet == nil else { return }
    pause()
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "The wallpaper isn't installed yet. Encoding is paused until you choose."
    let stopButton = alert.addButton(withTitle: stopTitle)
    stopButton.hasDestructiveAction = true
    alert.addButton(withTitle: "Keep Encoding").keyEquivalent = "\u{1b}"
    alert.beginSheetModal(for: window) { response in
        if response == .alertFirstButtonReturn { stop() } else { resume() }
    }
}

struct WindowCloseGuard: NSViewRepresentable {
    let needsConfirmation: Bool
    let onPause: () -> Void
    let onResume: () -> Void
    let onConfirm: () -> Void

    func makeNSView(context: Context) -> CloseGuardView {
        CloseGuardView()
    }

    func updateNSView(_ view: CloseGuardView, context: Context) {
        view.needsConfirmation = needsConfirmation
        view.onPause = onPause
        view.onResume = onResume
        view.onConfirm = onConfirm
    }
}

final class CloseGuardView: NSView {
    var needsConfirmation = false
    var onPause: () -> Void = {}
    var onResume: () -> Void = {}
    var onConfirm: () -> Void = {}
    private(set) var closeConfirmed = false
    private var proxy: GuardedWindowDelegate?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, proxy == nil else { return }
        let proxy = GuardedWindowDelegate(original: window.delegate, guardView: self)
        window.delegate = proxy
        self.proxy = proxy
    }

    func confirmClose(of window: NSWindow) {
        confirmStop(
            in: window, title: "Stop the install and close?", stopTitle: "Stop and Close",
            pause: onPause, resume: onResume
        ) { [weak self] in
            guard let self else { return }
            closeConfirmed = true
            onConfirm()
            window.close()
        }
    }
}

// SwiftUI owns the window's delegate, so this one answers windowShouldClose and forwards everything else.
final class GuardedWindowDelegate: NSObject, NSWindowDelegate {
    private let original: NSWindowDelegate?
    private weak var guardView: CloseGuardView?

    init(original: NSWindowDelegate?, guardView: CloseGuardView) {
        self.original = original
        self.guardView = guardView
    }

    var needsConfirmation: Bool {
        guard let guardView else { return false }
        return guardView.needsConfirmation && !guardView.closeConfirmed
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if needsConfirmation, let guardView {
            guardView.confirmClose(of: sender)
            return false
        }
        return original?.windowShouldClose?(sender) ?? true
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : nil
    }
}
