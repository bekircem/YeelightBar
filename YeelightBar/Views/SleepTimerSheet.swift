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
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceL) {
            header

            if state.selectedDeviceDelayOffMinutes > 0 {
                SleepTimerActiveStatusCard(
                    title: state.canControlSelectedDevice ? "Timer Active" : "Last Known Timer",
                    detail: activeTimerDetail,
                    accessibilityLabel: activeTimerAccessibilityLabel,
                    canCancel: canCancel,
                    unavailableReason: unavailableReason,
                    onCancel: cancelTimer
                )
            }

            timerSection
            appearanceSection

            if let notice {
                SleepTimerNoticeBanner(
                    message: notice.message,
                    systemImage: notice.symbolName,
                    color: notice.color,
                    accessibilityLabel: notice.accessibilityLabel
                )
            } else if state.selectedDeviceIsFlowing {
                Label(flowNoticeText, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(YeelightDesignTokens.spaceXL)
        .frame(
            width: YeelightDesignTokens.sleepTimerWidth,
            height: state.selectedDeviceDelayOffMinutes > 0
                ? YeelightDesignTokens.activeSleepTimerHeight
                : YeelightDesignTokens.sleepTimerHeight
        )
        .onAppear(perform: prepareInitialValues)
        .onChange(of: appearance) {
            notice = nil
        }
        .onChange(of: duration) { _, option in
            notice = nil
            if option == .custom {
                customDurationIsFocused = true
            }
        }
        .onChange(of: customMinutes) {
            notice = nil
        }
        .onChange(of: state.selectedDeviceID) { _, selectedDeviceID in
            if selectedDeviceID != deviceID {
                onDismiss()
            }
        }
    }

    private var header: some View {
        UtilitySheetHeader(
            title: "Sleep Timer",
            subtitle: "Turn off \(deviceName) after a delay. The timer runs on the light, even if YeelightBar quits.",
            systemImage: "moon.zzz.fill"
        )
        .help("Turn off \(deviceName) after a delay. The timer runs on the light, even if YeelightBar quits.")
    }

    private var timerSection: some View {
        GlassSection("Timer") {
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
                        onIncrement: { customMinutes = (customMinutes + 1).clamped(to: 1...60) },
                        onDecrement: { customMinutes = (customMinutes - 1).clamped(to: 1...60) }
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
    }

    private var appearanceSection: some View {
        GlassSection("Until Timer Ends", style: .tinted(appearanceAccentColor)) {
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
                    .accessibilityHint(compatiblePresets.isEmpty ? "No compatible static mode is available for this light." : "")
            }

            if appearance == .preset {
                Picker("Mode", selection: $selectedPresetID) {
                    ForEach(compatiblePresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .disabled(compatiblePresets.isEmpty)
            }

            SleepTimerAppearancePreview(
                title: appearanceTitle,
                summary: appearanceSummary
            ) {
                appearanceIcon
            }
        }
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

            GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
                HStack(spacing: YeelightDesignTokens.spaceS) {
                    Button("Cancel", role: .cancel) {
                        onDismiss()
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)

                    Button(state.selectedDeviceDelayOffMinutes > 0 ? "Replace Timer" : "Start Timer") {
                        startTimer()
                    }
                    .yeelightPrimaryButtonStyle()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                    .help(canStart ? "Start the sleep timer" : unavailableReason)
                }
            }
        }
    }

    private var activeTimerDetail: String {
        if state.canControlSelectedDevice {
            return "Turns off in about \(state.selectedDeviceDelayOffMinutes) min"
        }
        return "About \(state.selectedDeviceDelayOffMinutes) min when last connected"
    }

    private var appearanceAccentColor: Color {
        switch appearance {
        case .current:
            if let device = state.selectedDevice {
                return DeviceCardSnapshot(
                    device: device,
                    selectedDeviceID: state.selectedDeviceID
                ).ambientColor
            }
            return YeelightDesignTokens.accent
        case .warmDim:
            return LightAppearanceColorResolver.temperatureColor(
                kelvin: SleepTimerAppearance.warmDimTemperature
            )
        case .softRose:
            return Color(yeelightRGB: SleepTimerAppearance.softRoseRGB)
        case .preset:
            return selectedPreset?.swatchRGB.map { Color(yeelightRGB: $0) }
                ?? YeelightDesignTokens.accent
        }
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
