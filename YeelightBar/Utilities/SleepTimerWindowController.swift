import AppKit
import SwiftUI

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
            width: YeelightDesignTokens.sleepTimerWidth,
            height: state.selectedDeviceDelayOffMinutes > 0
                ? YeelightDesignTokens.activeSleepTimerHeight
                : YeelightDesignTokens.sleepTimerHeight
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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: YeelightDesignTokens.sleepTimerWidth,
                height: YeelightDesignTokens.sleepTimerHeight
            ),
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
