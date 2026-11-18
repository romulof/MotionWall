import AppKit
import SwiftUI

@main
struct MotionWallApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("MotionWall", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let guarded = sender.windows.first {
            $0.isVisible && ($0.delegate as? GuardedWindowDelegate)?.needsConfirmation == true
        }
        guard let guarded else { return .terminateNow }
        guarded.performClose(nil)
        return .terminateCancel
    }
}
