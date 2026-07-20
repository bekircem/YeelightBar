import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private weak var state: AppState?
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        guard let state else {
            return
        }

        let settingsWindow = window ?? makeWindow(state: state)
        window = settingsWindow

        NSApp.activate(ignoringOtherApps: true)

        if !settingsWindow.isVisible {
            settingsWindow.center()
        }

        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(state: AppState) -> NSWindow {
        let controller = NSHostingController(
            rootView: SettingsView()
                .environmentObject(state)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "YeelightBar Settings"
        window.contentViewController = controller
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("YeelightBarSettingsWindow")

        return window
    }
}
