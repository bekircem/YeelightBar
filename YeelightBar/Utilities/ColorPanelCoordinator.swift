import AppKit

@MainActor
final class ColorPanelCoordinator: NSObject {
    var onColorChange: (@MainActor (NSColor) -> Void)?
    var onPanelClose: (@MainActor () -> Void)?

    private var colorPanel: NSColorPanel?

    var isVisible: Bool {
        colorPanel?.isVisible == true
    }

    func show(color: NSColor) {
        let panel = configuredPanel()
        panel.color = color.usingColorSpace(.sRGB) ?? color

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        colorPanel?.orderOut(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configuredPanel() -> NSColorPanel {
        if let colorPanel {
            return colorPanel
        }

        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: panel
        )

        colorPanel = panel
        return panel
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onColorChange?(sender.color.usingColorSpace(.sRGB) ?? sender.color)
    }

    @objc private func colorPanelWillClose(_ notification: Notification) {
        onPanelClose?()
    }
}
