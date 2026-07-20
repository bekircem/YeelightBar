import AppKit
import Foundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedPanel: SettingsPanel = .general
    @State private var confirmForgetDevices = false
    @State private var confirmResetPreferences = false
    @State private var recordingShortcutAction: KeyboardShortcutAction?
    @State private var recordingPresetShortcutID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detail
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Forget all saved devices?", isPresented: $confirmForgetDevices) {
            Button("Forget Devices", role: .destructive) {
                state.forgetDevices()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Manual and discovered devices will be removed from YeelightBar.")
        }
        .alert("Reset all YeelightBar settings?", isPresented: $confirmResetPreferences) {
            Button("Reset Settings", role: .destructive) {
                state.resetPreferences()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Preferences, saved devices, and the selected device will return to defaults.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            ForEach(SettingsPanel.allCases) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: panel.systemImage)
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 22)

                        Text(panel.title)
                            .font(.body.weight(selectedPanel == panel ? .semibold : .regular))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selectedPanel == panel ? Color.accentColor.opacity(0.18) : Color.clear)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedPanel == panel ? .primary : .secondary)
                .accessibilityLabel(panel.title)
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        if selectedPanel == .modes {
            VStack(alignment: .leading, spacing: 20) {
                header(for: selectedPanel)
                ModesSettingsView()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(for: selectedPanel)
                    panelContent(for: selectedPanel)
                }
                .padding(28)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func header(for panel: SettingsPanel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(panel.title, systemImage: panel.systemImage)
                .font(.title.weight(.semibold))

            Text(panel.subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func panelContent(for panel: SettingsPanel) -> some View {
        switch panel {
        case .general:
            generalPanel
        case .devices:
            devicesPanel
        case .modes:
            ModesSettingsView()
        case .network:
            networkPanel
        case .controls:
            controlsPanel
        case .shortcuts:
            shortcutsPanel
        case .appearance:
            appearancePanel
        case .diagnostics:
            diagnosticsPanel
        case .advanced:
            advancedPanel
        }
    }

    private var generalPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Startup") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))

                if state.launchAtLoginRequiresApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Label("macOS requires approval before YeelightBar can open at login.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items…") {
                            state.openLoginItemsSettings()
                        }
                    }
                }

                Picker("Menu bar icon", selection: Binding(
                    get: { state.menuBarIconStyle },
                    set: { state.setMenuBarIconStyle($0) }
                )) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            SettingsSection("Language") {
                LabeledContent("App language", value: "System Default")
                Text("The first version keeps app copy in English for consistency with the existing interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection("App") {
                LabeledContent("YeelightBar", value: state.appVersionText)

                Button {
                    state.checkForUpdates()
                } label: {
                    Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
                }

                Button(role: .destructive) {
                    state.quit()
                } label: {
                    Label("Quit YeelightBar", systemImage: "power")
                }
            }
        }
    }

    private var devicesPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Selected Device") {
                Picker("Device", selection: Binding(
                    get: { state.selectedDeviceID },
                    set: { state.selectDevice(id: $0) }
                )) {
                    Text("None").tag(Optional<String>.none)
                    ForEach(state.devices) { device in
                        Text(device.displayName).tag(Optional(device.id))
                    }
                }

                if let selectedDevice = state.selectedDevice {
                    LabeledContent("Name", value: selectedDevice.displayName)
                    LabeledContent("Model", value: selectedDevice.model.isEmpty ? "Unknown" : selectedDevice.model)
                    LabeledContent("Endpoint", value: "\(selectedDevice.host):\(selectedDevice.port)")
                    LabeledContent("Online", value: selectedDevice.state.online ? "Yes" : "No")
                } else {
                    Text("No device is selected.")
                        .foregroundStyle(.secondary)
                }
            }

            if !state.discoveredCandidates.isEmpty {
                SettingsSection(
                    "Discovered Bulbs",
                    description: "Discovered bulbs are not trusted or contacted until you add them."
                ) {
                    ForEach(state.discoveredCandidates) { candidate in
                        HStack(spacing: 10) {
                            Image(systemName: candidate.endpointChanged ? "exclamationmark.triangle" : "lightbulb")
                                .foregroundStyle(candidate.endpointChanged ? .orange : .secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.device.displayName)
                                Text("\(candidate.device.host):\(candidate.device.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if candidate.endpointChanged {
                                    Text("This saved device is advertising a new endpoint.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Spacer()
                            Button(candidate.endpointChanged ? "Approve Change" : "Add") {
                                state.trustDiscoveredCandidate(id: candidate.id)
                            }
                            Button {
                                state.dismissDiscoveredCandidate(id: candidate.id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("Dismiss discovered bulb")
                            .accessibilityLabel("Dismiss \(candidate.device.displayName)")
                        }
                    }
                }
            }

            SettingsSection("Manual Device") {
                HStack(spacing: 8) {
                    TextField("192.168.1.42", text: Binding(
                        get: { state.manualHost },
                        set: { state.manualHost = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    TextField(String(state.defaultManualPort), text: Binding(
                        get: { state.manualPort },
                        set: { state.manualPort = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                    Button {
                        state.addManualDevice()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(!state.canAddManualDevice)
                }
            }

            SettingsSection("Device Management") {
                HStack {
                    Button(role: .destructive) {
                        state.removeSelectedDevice()
                    } label: {
                        Label("Remove Selected Device", systemImage: "trash")
                    }
                    .disabled(!state.hasSelectedDevice)

                    Button(role: .destructive) {
                        confirmForgetDevices = true
                    } label: {
                        Label("Forget All Devices", systemImage: "trash.slash")
                    }
                    .disabled(state.devices.isEmpty)
                }
            }
        }
    }

    private var networkPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Discovery") {
                HStack {
                    Slider(value: Binding(
                        get: { state.discoveryRetryInterval },
                        set: { state.setDiscoveryRetryInterval($0) }
                    ), in: 5...120, step: 5)

                    Text("\(Int(state.discoveryRetryInterval)) s")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }

                LabeledContent("Last discovery", value: state.lastDiscoveryText)

                Button {
                    state.discover()
                } label: {
                    Label("Discover Now", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            SettingsSection("Manual Connection") {
                Stepper(value: Binding(
                    get: { Int(state.defaultManualPort) },
                    set: { state.setDefaultManualPort(UInt16($0.clamped(to: 1...65535))) }
                ), in: 1...65535) {
                    LabeledContent("Default Yeelight port", value: "\(state.defaultManualPort)")
                }

                Text("Yeelight LAN Control must be enabled in the Yeelight iOS app, and the Mac must be on the same local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection("Supported Devices", description: "Compatibility is based on the local Yeelight LAN protocol, not the brand name alone.") {
                supportedDeviceRow(
                    title: "Supported",
                    detail: "Yeelight Wi-Fi bulbs, strips, ceiling, desk, and ambient lights with LAN Control enabled.",
                    systemImage: "checkmark.circle"
                )

                supportedDeviceRow(
                    title: "May work",
                    detail: "Xiaomi, Mijia, or Yeelink lights only if they expose yeelight://host:55443 on your LAN.",
                    systemImage: "questionmark.circle"
                )

                supportedDeviceRow(
                    title: "Not supported",
                    detail: "Cloud-only, BLE Mesh, Zigbee, Matter, and HomeKit-only devices without Yeelight LAN TCP control.",
                    systemImage: "xmark.circle"
                )
            }
        }
    }

    private var controlsPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Transitions") {
                Picker("Smooth transition", selection: Binding(
                    get: { state.transitionDuration },
                    set: { state.setTransitionDuration($0) }
                )) {
                    Text("Sudden").tag(30)
                    Text("250 ms").tag(250)
                    Text("500 ms").tag(500)
                    Text("1 s").tag(1000)
                    Text("2 s").tag(2000)
                    Text("5 s").tag(5000)
                }
            }

            SettingsSection("Command Timing") {
                Stepper(value: Binding(
                    get: { state.brightnessDebounceMilliseconds },
                    set: { state.setBrightnessDebounceMilliseconds($0) }
                ), in: 30...1000, step: 10) {
                    LabeledContent("Brightness debounce", value: "\(state.brightnessDebounceMilliseconds) ms")
                }

                Stepper(value: Binding(
                    get: { state.colorDebounceMilliseconds },
                    set: { state.setColorDebounceMilliseconds($0) }
                ), in: 30...1000, step: 10) {
                    LabeledContent("Color debounce", value: "\(state.colorDebounceMilliseconds) ms")
                }

                Stepper(value: Binding(
                    get: { state.commandTimeout },
                    set: { state.setCommandTimeout($0) }
                ), in: 1...30, step: 0.5) {
                    LabeledContent("Command timeout", value: formattedSeconds(state.commandTimeout))
                }

                Stepper(value: Binding(
                    get: { state.reconnectInterval },
                    set: { state.setReconnectInterval($0) }
                ), in: 1...60, step: 1) {
                    LabeledContent("Reconnect interval", value: formattedSeconds(state.reconnectInterval))
                }
            }
        }
    }

    private var shortcutsPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Global Shortcuts", description: "Shortcuts work while other apps are active. Conflicts are detected when macOS rejects a registration.") {
                Toggle("Enable Global Shortcuts", isOn: Binding(
                    get: { state.shortcutsEnabled },
                    set: { state.setShortcutsEnabled($0) }
                ))

                Stepper(value: Binding(
                    get: { state.shortcutBrightnessStep },
                    set: { state.setShortcutBrightnessStep($0) }
                ), in: 1...25, step: 1) {
                    LabeledContent("Brightness step", value: "\(state.shortcutBrightnessStep)%")
                }

                HStack {
                    Button {
                        state.resetShortcutsToDefaults()
                    } label: {
                        Label("Reset Shortcuts", systemImage: "arrow.counterclockwise")
                    }

                    Spacer()
                }
            }

            SettingsSection("Actions") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(KeyboardShortcutAction.allCases) { action in
                        shortcutRow(action)
                    }
                }
            }

            SettingsSection("Direct Mode Shortcuts", description: "Assign a global shortcut to a specific mode, color, or flow.") {
                VStack(alignment: .leading, spacing: 12) {
                    if state.presetShortcuts.isEmpty {
                        Text("No direct mode shortcuts configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.presetShortcuts) { shortcut in
                            presetShortcutRow(shortcut)
                        }
                    }

                    Button {
                        _ = state.addPresetShortcut()
                    } label: {
                        Label("Add Mode Shortcut", systemImage: "plus")
                    }
                }
            }
        }
        .onDisappear {
            if recordingShortcutAction != nil || recordingPresetShortcutID != nil {
                recordingShortcutAction = nil
                recordingPresetShortcutID = nil
                state.endShortcutRecording()
            }
        }
    }

    private var appearancePanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Popover") {
                HStack {
                    Slider(value: Binding(
                        get: { state.popoverWidth },
                        set: { state.setPopoverWidth($0) }
                    ), in: 300...520, step: 10)

                    Text("\(Int(state.popoverWidth)) px")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }

                Picker("Control density", selection: Binding(
                    get: { state.controlDisplayMode },
                    set: { state.setControlDisplayMode($0) }
                )) {
                    ForEach(ControlDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Show color control", isOn: Binding(
                    get: { state.showColorControl },
                    set: { state.setShowColorControl($0) }
                ))
            }
        }
    }

    private var diagnosticsPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Connection") {
                LabeledContent("Status", value: state.status.title)
                LabeledContent("Ready", value: state.connectionReady ? "Yes" : "No")
                LabeledContent("Endpoint", value: state.selectedDeviceEndpoint.isEmpty ? "None" : state.selectedDeviceEndpoint)
                LabeledContent("Last error", value: state.lastErrorMessage)
            }

            SettingsSection("Selected Device") {
                LabeledContent("Capabilities", value: state.selectedDeviceCapabilitiesText)

                Text("Compatibility is determined by the LAN endpoint and reported capabilities from the device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        state.refreshSelectedDeviceStateForUser()
                    } label: {
                        Label("Refresh State", systemImage: "arrow.clockwise")
                    }
                    .disabled(!state.hasSelectedDevice)

                    Button {
                        state.testSelectedDeviceConnection()
                    } label: {
                        Label("Test Command", systemImage: "stethoscope")
                    }
                    .disabled(!state.hasSelectedDevice)
                }
            }

            SettingsSection("Log") {
                Toggle("Debug logging", isOn: Binding(
                    get: { state.debugLoggingEnabled },
                    set: { state.setDebugLoggingEnabled($0) }
                ))

                if state.diagnosticEvents.isEmpty {
                    Text("No diagnostic events yet.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(state.diagnosticEvents.enumerated()), id: \.offset) { _, event in
                            Text(event)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    state.clearDiagnosticsLog()
                } label: {
                    Label("Clear Log", systemImage: "xmark.circle")
                }
                .disabled(state.diagnosticEvents.isEmpty)
            }
        }
    }

    private var advancedPanel: some View {
        VStack(spacing: 16) {
            SettingsSection("Preferences") {
                HStack {
                    Button {
                        state.exportPreferences()
                    } label: {
                        Label("Export Settings JSON", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        state.importPreferences()
                    } label: {
                        Label("Import Settings JSON", systemImage: "square.and.arrow.down")
                    }
                }
            }

            SettingsSection("Reset") {
                Button(role: .destructive) {
                    confirmResetPreferences = true
                } label: {
                    Label("Reset Preferences", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                }
            }

            SettingsSection("Debug Info") {
                LabeledContent("Saved devices", value: "\(state.devices.count)")
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "Unknown")
                LabeledContent("Local network", value: "Yeelight LAN / TCP JSON")
            }
        }
    }

    private func supportedDeviceRow(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func shortcutRow(_ action: KeyboardShortcutAction) -> some View {
        let shortcut = state.shortcut(for: action)
        let status = state.shortcutStatus(for: action)
        let isRecording = recordingShortcutAction == action

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.body.weight(.medium))
                    Text(action.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ShortcutStatusBadge(status: status)

                Text(shortcut.combination?.displayString ?? "Not Set")
                    .font(.body.monospaced())
                    .foregroundStyle(shortcut.combination == nil ? .secondary : .primary)
                    .frame(minWidth: 92, alignment: .trailing)

                Button {
                    if isRecording {
                        recordingShortcutAction = nil
                        state.endShortcutRecording()
                    } else {
                        recordingShortcutAction = action
                        recordingPresetShortcutID = nil
                        state.beginShortcutRecording()
                    }
                } label: {
                    Label(isRecording ? "Cancel" : "Record", systemImage: isRecording ? "xmark" : "keyboard")
                }

                Button {
                    state.clearShortcut(action: action)
                } label: {
                    Label("Clear", systemImage: "delete.left")
                }
                .disabled(shortcut.combination == nil)
            }

            if isRecording {
                HStack(spacing: 8) {
                    Label("Press a new shortcut now. Use at least two modifier keys.", systemImage: "keyboard.badge.eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Esc cancels")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
                .overlay {
                    ShortcutCaptureView { combination in
                        if state.assignShortcut(action: action, combination: combination) {
                            recordingShortcutAction = nil
                            state.endShortcutRecording()
                        }
                    } onCancel: {
                        recordingShortcutAction = nil
                        state.endShortcutRecording()
                    }
                    .frame(width: 0, height: 0)
                }
            }

            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func presetShortcutRow(_ shortcut: PresetShortcut) -> some View {
        let currentShortcut = state.presetShortcut(for: shortcut.id) ?? shortcut
        let status = state.presetShortcutStatus(for: shortcut.id)
        let isRecording = recordingPresetShortcutID == shortcut.id
        let selectedPreset = state.availablePresets.first { $0.id == currentShortcut.presetID }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: selectedPreset?.symbolName ?? "sparkles")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.secondary)

                Picker("Mode", selection: Binding(
                    get: { state.presetShortcut(for: shortcut.id)?.presetID ?? "" },
                    set: { state.setPresetShortcutPreset(id: shortcut.id, presetID: $0.isEmpty ? nil : $0) }
                )) {
                    Text("Choose Mode").tag("")

                    if let presetID = currentShortcut.presetID,
                       !state.availablePresets.contains(where: { $0.id == presetID }) {
                        Text("Mode Missing").tag(presetID)
                    }

                    ForEach(state.availablePresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)

                Spacer()

                ShortcutStatusBadge(status: status)

                Text(currentShortcut.combination?.displayString ?? "Not Set")
                    .font(.body.monospaced())
                    .foregroundStyle(currentShortcut.combination == nil ? .secondary : .primary)
                    .frame(minWidth: 92, alignment: .trailing)

                Button {
                    if isRecording {
                        recordingPresetShortcutID = nil
                        state.endShortcutRecording()
                    } else {
                        recordingShortcutAction = nil
                        recordingPresetShortcutID = shortcut.id
                        state.beginShortcutRecording()
                    }
                } label: {
                    Label(isRecording ? "Cancel" : "Record", systemImage: isRecording ? "xmark" : "keyboard")
                }

                Button {
                    state.clearPresetShortcut(id: shortcut.id)
                } label: {
                    Label("Clear", systemImage: "delete.left")
                }
                .disabled(currentShortcut.combination == nil)

                Button(role: .destructive) {
                    state.deletePresetShortcut(id: shortcut.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete direct mode shortcut")
            }

            if isRecording {
                HStack(spacing: 8) {
                    Label("Press a new shortcut now. Use at least two modifier keys.", systemImage: "keyboard.badge.eye")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Esc cancels")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                }
                .overlay {
                    ShortcutCaptureView { combination in
                        if state.assignPresetShortcut(id: shortcut.id, combination: combination) {
                            recordingPresetShortcutID = nil
                            state.endShortcutRecording()
                        }
                    } onCancel: {
                        recordingPresetShortcutID = nil
                        state.endShortcutRecording()
                    }
                    .frame(width: 0, height: 0)
                }
            }

            if let detail = status.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedSeconds(_ value: Double) -> String {
        String(format: value == floor(value) ? "%.0f s" : "%.1f s", value)
    }

}

private struct ShortcutStatusBadge: View {
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

private struct ShortcutCaptureView: NSViewRepresentable {
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

private final class ShortcutCaptureNSView: NSView {
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

private struct SettingsSection<Content: View>: View {
    private let title: String
    private let description: String?
    @ViewBuilder private let content: Content

    init(_ title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)

                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum SettingsPanel: String, CaseIterable, Identifiable {
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
