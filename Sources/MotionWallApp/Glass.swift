import AppKit
import SwiftUI

final class WindowGlassView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
    }
}

struct WindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowGlassView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct CenteredWindowTitle: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .principal) {
                Text(title).font(.headline)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .principal) {
                Text(title).font(.headline)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }
}
