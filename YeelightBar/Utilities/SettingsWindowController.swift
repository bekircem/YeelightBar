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

@MainActor
final class SleepTimerWindowController: NSObject, NSWindowDelegate {
    private weak var state: AppState?
    private var window: NSPanel?

    init(state: AppState) {
        self.state = state
    }

    func show(deviceID: String) {
        guard let state else {
            return
        }

        let timerWindow = window ?? makeWindow()
        window = timerWindow
        timerWindow.contentViewController = NSHostingController(
            rootView: SleepTimerSheet(
                deviceID: deviceID,
                onDismiss: { [weak self] in
                    self?.close()
                }
            )
            .environmentObject(state)
        )
        timerWindow.setContentSize(NSSize(
            width: 440,
            height: state.selectedDeviceDelayOffMinutes > 0 ? 400 : 370
        ))

        NSApp.activate(ignoringOtherApps: true)

        if !timerWindow.isVisible {
            timerWindow.center()
        }

        timerWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 370),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        panel.title = "Sleep Timer"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.delegate = self

        return panel
    }
}
