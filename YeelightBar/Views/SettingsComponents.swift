import AppKit
import SwiftUI

struct ShortcutStatusBadge: View {
    let status: HotKeyRegistrationStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                Capsule()
                    .fill(backgroundColor)
            }
    }

    private var foregroundColor: Color {
        switch status {
        case .registered:
            return .green
        case .conflict, .invalid, .failed, .missingPreset:
            return .red
        case .disabled, .unassigned:
            return .secondary
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .registered:
            return Color.green.opacity(0.16)
        case .conflict, .invalid, .failed, .missingPreset:
            return Color.red.opacity(0.14)
        case .disabled, .unassigned:
            return Color.secondary.opacity(0.12)
        }
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    let onCapture: (HotKeyCombination) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class ShortcutCaptureNSView: NSView {
    var onCapture: ((HotKeyCombination) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        guard let combination = HotKeyCombination(event: event) else {
            NSSound.beep()
            return
        }

        onCapture?(combination)
    }
}

enum SettingsSectionStyle {
    case standard
    case glass(GlassSurfaceStyle)
}

struct SettingsSection<Content: View>: View {
    private let title: String
    private let description: String?
    private let style: SettingsSectionStyle
    @ViewBuilder private let content: Content

    init(
        _ title: String,
        description: String? = nil,
        style: SettingsSectionStyle = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.description = description
        self.style = style
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        switch style {
        case .standard:
            GroupBox {
                sectionContent
            } label: {
                sectionLabel
            }
            .groupBoxStyle(.automatic)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .glass(let glassStyle):
            GlassSection(title, subtitle: description, style: glassStyle) {
                sectionContent
            }
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
            content
        }
        .padding(.vertical, YeelightDesignTokens.spaceXS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sectionLabel: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
            Text(title)
                .font(.headline)

            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

enum SettingsPanel: String, CaseIterable, Hashable, Identifiable {
    case general
    case devices
    case modes
    case network
    case controls
    case shortcuts
    case appearance
    case diagnostics
    case advanced

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .devices:
            return "Devices"
        case .modes:
            return "Modes & Flows"
        case .network:
            return "Discovery & Network"
        case .controls:
            return "Controls"
        case .shortcuts:
            return "Shortcuts"
        case .appearance:
            return "Appearance"
        case .diagnostics:
            return "Diagnostics"
        case .advanced:
            return "Advanced"
        }
    }

    var subtitle: String {
        switch self {
        case .general:
            return "Startup and app-level behavior."
        case .devices:
            return "Saved bulbs, manual devices, and selected device details."
        case .modes:
            return "Reusable light modes, favorites, and local color flows."
        case .network:
            return "LAN discovery, retry timing, and default connection values."
        case .controls:
            return "Transition, debounce, timeout, and reconnect behavior."
        case .shortcuts:
            return "Global keyboard shortcuts and shortcut recording."
        case .appearance:
            return "Menubar popover layout and control visibility."
        case .diagnostics:
            return "Connection state, capabilities, test commands, and logs."
        case .advanced:
            return "Import, export, reset, and debug information."
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .devices:
            return "lightbulb"
        case .modes:
            return "sparkles"
        case .network:
            return "network"
        case .controls:
            return "slider.horizontal.3"
        case .shortcuts:
            return "keyboard"
        case .appearance:
            return "paintbrush"
        case .diagnostics:
            return "waveform.path.ecg"
        case .advanced:
            return "wrench.and.screwdriver"
        }
    }
}
