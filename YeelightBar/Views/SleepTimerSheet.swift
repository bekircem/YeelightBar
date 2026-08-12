import AppKit
import SwiftUI

struct SleepTimerSheet: View {
    @EnvironmentObject private var state: AppState

    let deviceID: String?
    let onDismiss: () -> Void

    @State private var duration: SleepTimerDuration = .minutes30
    @State private var customMinutes = 30
    @State private var appearance: SleepTimerAppearanceChoice = .current
    @State private var selectedPresetID = ""
    @State private var isSubmitting = false
    @State private var notice: SleepTimerNotice?
    @FocusState private var customDurationIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if state.selectedDeviceDelayOffMinutes > 0 {
                activeTimerCard
            }

            Form {
                Section("Timer") {
                    Picker("Duration", selection: $duration) {
                        ForEach(SleepTimerDuration.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if duration == .custom {
                        HStack {
                            Text("Custom duration")

                            Spacer()

                            TextField("Minutes", value: $customMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 58)
                                .focused($customDurationIsFocused)

                            Stepper(
                                "Minutes",
                                onIncrement: {
                                    customMinutes = (customMinutes + 1).clamped(to: 1...60)
                                },
                                onDecrement: {
                                    customMinutes = (customMinutes - 1).clamped(to: 1...60)
                                }
                            )
                                .labelsHidden()

                            Text("min")
                                .foregroundStyle(.secondary)
                        }

                        if !customDurationIsValid {
                            Label("Enter a duration from 1 to 60 minutes.", systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.red)
                                .accessibilityLabel("Invalid duration. Enter a value from 1 to 60 minutes.")
                        }
                    }
                }

                Section("Until Timer Ends") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Keep Current")
                            .tag(SleepTimerAppearanceChoice.current)

                        Text("Warm Dim")
                            .tag(SleepTimerAppearanceChoice.warmDim)
                            .disabled(!supportsWarmDim)
                            .accessibilityHint(supportsWarmDim ? "" : "Unavailable because this light cannot set a warm dim appearance.")

                        Text("Soft Rose")
                            .tag(SleepTimerAppearanceChoice.softRose)
                            .disabled(!supportsSoftRose)
                            .accessibilityHint(supportsSoftRose ? "" : "Unavailable because this light cannot set color.")

                        Text("Choose Mode…")
                            .tag(SleepTimerAppearanceChoice.preset)
                            .disabled(compatiblePresets.isEmpty)
                            .accessibilityHint(compatiblePresets.isEmpty ? "No compatible static modes are available for this light." : "")
                    }

                    if appearance == .preset {
                        Picker("Mode", selection: $selectedPresetID) {
                            ForEach(compatiblePresets) { preset in
                                Text(preset.title).tag(preset.id)
                            }
                        }
                        .disabled(compatiblePresets.isEmpty)
                    }

                    appearancePreview
                }
            }
            .formStyle(.grouped)

            if let notice {
                Label(notice.message, systemImage: notice.symbolName)
                    .font(.caption)
                    .foregroundStyle(notice.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(notice.accessibilityLabel)
            } else if state.selectedDeviceIsFlowing {
                Label(flowNoticeText, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(20)
        .frame(width: 440, height: state.selectedDeviceDelayOffMinutes > 0 ? 400 : 370)
        .onAppear(perform: prepareInitialValues)
        .onChange(of: appearance) { _ in
            notice = nil
        }
        .onChange(of: duration) { option in
            notice = nil
            if option == .custom {
                customDurationIsFocused = true
            }
        }
        .onChange(of: customMinutes) { _ in
            notice = nil
        }
        .onChange(of: state.selectedDeviceID) { selectedDeviceID in
            if selectedDeviceID != deviceID {
                onDismiss()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sleep Timer")
                .font(.title2.weight(.semibold))

            Text("Turn off \(deviceName) after a delay. The timer runs on the light, even if YeelightBar quits.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help("Turn off \(deviceName) after a delay. The timer runs on the light, even if YeelightBar quits.")
        }
    }

    private var activeTimerCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.canControlSelectedDevice ? "Timer Active" : "Last Known Timer")
                    .font(.callout.weight(.medium))
                Text(activeTimerDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(activeTimerAccessibilityLabel)

            Spacer()

            Button("Cancel Timer") {
                cancelTimer()
            }
            .controlSize(.small)
            .disabled(!canCancel)
            .help(canCancel ? "Cancel the selected light's sleep timer" : unavailableReason)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var appearancePreview: some View {
        HStack(spacing: 10) {
            appearanceIcon

            VStack(alignment: .leading, spacing: 1) {
                Text(appearanceTitle)
                    .font(.callout.weight(.medium))
                Text(appearanceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var appearanceIcon: some View {
        switch appearance {
        case .current:
            Image(systemName: state.selectedDeviceIsFlowing ? "waveform" : "lightbulb")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        case .warmDim:
            Image(systemName: "thermometer.sun.fill")
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
        case .softRose:
            Circle()
                .fill(Color(yeelightRGB: SleepTimerAppearance.softRoseRGB))
                .frame(width: 22, height: 22)
                .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }
                .frame(width: 24, height: 24)
        case .preset:
            if let preset = selectedPreset {
                if let rgb = preset.swatchRGB {
                    Circle()
                        .fill(Color(yeelightRGB: rgb))
                        .frame(width: 22, height: 22)
                        .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: preset.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            } else {
                Image(systemName: "square.stack")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
    }

    private var footer: some View {
        HStack {
            if isSubmitting {
                ProgressView()
                    .controlSize(.small)
                Text("Updating timer…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !state.selectedDeviceSupportsSleepTimer {
                Label("Timer not supported", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("This light does not advertise sleep timer support.")
            } else if !state.canControlSelectedDevice {
                Label("Light unavailable", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !state.isPowerOn {
                Label("Turn on the light first", systemImage: "power")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Cancel", role: .cancel) {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSubmitting)

            Button(state.selectedDeviceDelayOffMinutes > 0 ? "Replace Timer" : "Start Timer") {
                startTimer()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canStart)
            .help(canStart ? "Start the sleep timer" : unavailableReason)
        }
    }

    private var activeTimerDetail: String {
        if state.canControlSelectedDevice {
            return "Turns off in about \(state.selectedDeviceDelayOffMinutes) min"
        }
        return "About \(state.selectedDeviceDelayOffMinutes) min when last connected"
    }

    private var flowNoticeText: String {
        appearance == .current
            ? "The current flow will continue until the light turns off."
            : "Applying this appearance will stop the current flow."
    }

    private var activeTimerAccessibilityLabel: String {
        if state.canControlSelectedDevice {
            return "Sleep Timer active, turns off in about \(state.selectedDeviceDelayOffMinutes) minutes"
        }
        return "Last known Sleep Timer, about \(state.selectedDeviceDelayOffMinutes) minutes when last connected. Reconnect to verify."
    }

    private var selectedPreset: LightPreset? {
        compatiblePresets.first { $0.id == selectedPresetID }
    }

    private var compatiblePresets: [LightPreset] {
        state.compatibleSleepTimerPresets.filter { $0.kind != .flow }
    }

    private var selectedMinutes: Int {
        duration.minutes ?? customMinutes
    }

    private var customDurationIsValid: Bool {
        duration != .custom || SleepTimerMinutes.validRange.contains(customMinutes)
    }

    private var selectedAppearance: SleepTimerAppearance? {
        switch appearance {
        case .current:
            return .current
        case .warmDim:
            return supportsWarmDim ? .warmDim : nil
        case .softRose:
            return supportsSoftRose ? .softRose : nil
        case .preset:
            guard selectedPreset != nil else {
                return nil
            }
            return .preset(id: selectedPresetID)
        }
    }

    private var canStart: Bool {
        state.selectedDeviceID == deviceID
            && state.selectedDeviceSupportsSleepTimer
            && state.canControlSelectedDevice
            && state.isPowerOn
            && customDurationIsValid
            && selectedAppearance != nil
            && !isSubmitting
    }

    private var canCancel: Bool {
        state.selectedDeviceID == deviceID
            && state.selectedDeviceSupportsSleepTimer
            && state.canControlSelectedDevice
            && !isSubmitting
    }

    private var supportsWarmDim: Bool {
        state.selectedDeviceSupportsSleepTimerWarmDim
    }

    private var supportsSoftRose: Bool {
        state.selectedDeviceSupportsSleepTimerSoftRose
    }

    private var deviceName: String {
        state.selectedDevice?.displayName ?? "the selected light"
    }

    private var appearanceTitle: String {
        switch appearance {
        case .current:
            return state.selectedDeviceIsFlowing ? "Keep Current Flow" : "Keep Current"
        case .warmDim:
            return "Warm Dim"
        case .softRose:
            return "Soft Rose"
        case .preset:
            return selectedPreset?.title ?? "Choose Mode"
        }
    }

    private var appearanceSummary: String {
        switch appearance {
        case .current:
            return state.selectedDeviceIsFlowing
                ? "The active flow keeps running until the timer ends."
                : "Leave the light exactly as it is until the timer ends."
        case .warmDim:
            return supportsWarmDim
                ? "A calm \(SleepTimerAppearance.warmDimTemperature)K glow at \(SleepTimerAppearance.builtInBrightness)% brightness."
                : "Not supported by this light."
        case .softRose:
            return supportsSoftRose
                ? "A very low soft-rose glow at \(SleepTimerAppearance.builtInBrightness)% brightness."
                : "Color is not supported by this light."
        case .preset:
            return selectedPreset?.summary ?? "No compatible static mode is available."
        }
    }

    private var unavailableReason: String {
        if state.selectedDeviceID != deviceID {
            return "The selected light changed. Close this sheet and try again."
        }
        if !state.selectedDeviceSupportsSleepTimer {
            return "This light does not advertise sleep timer support."
        }
        if !state.canControlSelectedDevice {
            return "Reconnect to the light to manage its sleep timer."
        }
        if !state.isPowerOn {
            return "Turn on the light before starting a sleep timer."
        }
        if selectedAppearance == nil {
            return "Choose an appearance supported by this light."
        }
        return "A sleep timer operation is in progress."
    }

    private func prepareInitialValues() {
        if state.selectedDeviceDelayOffMinutes > 0 {
            let remaining = state.selectedDeviceDelayOffMinutes.clamped(to: 1...60)
            if let option = SleepTimerDuration(minutes: remaining) {
                duration = option
            } else {
                duration = .custom
                customMinutes = remaining
            }
        }

        selectedPresetID = compatiblePresets.first?.id ?? ""
    }

    private func startTimer() {
        guard canStart, let selectedAppearance else {
            return
        }

        notice = nil
        isSubmitting = true

        Task { @MainActor in
            let result = await state.scheduleSleepTimer(
                minutes: selectedMinutes,
                appearance: selectedAppearance
            )

            isSubmitting = false

            switch result {
            case .success:
                onDismiss()
            case .timerStartedAppearanceFailed(let message):
                presentNotice(.warning(message))
            case .verificationPending(let message):
                presentNotice(.warning(message))
            case .failure(let message):
                presentNotice(.error(message))
            }
        }
    }

    private func cancelTimer() {
        guard canCancel else {
            return
        }

        notice = nil
        isSubmitting = true

        Task { @MainActor in
            let didCancel = await state.cancelSleepTimer()
            isSubmitting = false

            if didCancel {
                onDismiss()
            } else {
                presentNotice(.error("The timer could not be cancelled. Reconnect to the light and try again."))
            }
        }
    }

    private func presentNotice(_ newNotice: SleepTimerNotice) {
        notice = newNotice
        guard let application = NSApp else {
            return
        }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: newNotice.accessibilityLabel,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

private enum SleepTimerDuration: String, CaseIterable, Identifiable {
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes15: return "15 min"
        case .minutes30: return "30 min"
        case .minutes45: return "45 min"
        case .minutes60: return "1 hr"
        case .custom: return "Custom"
        }
    }

    var minutes: Int? {
        switch self {
        case .minutes15: return 15
        case .minutes30: return 30
        case .minutes45: return 45
        case .minutes60: return 60
        case .custom: return nil
        }
    }

    init?(minutes: Int) {
        switch minutes {
        case 15: self = .minutes15
        case 30: self = .minutes30
        case 45: self = .minutes45
        case 60: self = .minutes60
        default: return nil
        }
    }
}

private enum SleepTimerAppearanceChoice: String, Hashable {
    case current
    case warmDim
    case softRose
    case preset
}

private enum SleepTimerNotice {
    case warning(String)
    case error(String)

    var message: String {
        switch self {
        case .warning(let message), .error(let message): return message
        }
    }

    var symbolName: String {
        switch self {
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .warning(let message): return "Warning: \(message)"
        case .error(let message): return "Error: \(message)"
        }
    }
}
