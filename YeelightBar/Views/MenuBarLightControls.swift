import SwiftUI

struct MenuBarLightControls: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
            if !state.canControlSelectedDevice {
                unavailableNotice
            }

            powerAndBrightness
            sleepTimerRow
            lightModeControls
        }
    }

    private var powerAndBrightness: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
            HStack {
                Label("Power", systemImage: state.isPowerOn ? "lightbulb.fill" : "lightbulb")
                    .font(.subheadline.weight(.medium))

                Spacer()

                Toggle("Power", isOn: Binding(
                    get: { state.isPowerOn },
                    set: { state.setPower($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(YeelightDesignTokens.accent)
                .disabled(!state.canControlSelectedDevice)
            }

            controlSlider(
                title: "Brightness",
                systemImage: "sun.max",
                value: Binding(
                    get: { state.brightness },
                    set: { state.setBrightness($0) }
                ),
                range: 1...100,
                valueLabel: "\(Int(state.brightness.rounded()))%"
            )
        }
    }

    private var sleepTimerRow: some View {
        Button {
            state.showSleepTimer()
        } label: {
            HStack(spacing: YeelightDesignTokens.spaceS) {
                Image(systemName: state.selectedDeviceDelayOffMinutes > 0 ? "moon.zzz.fill" : "moon.zzz")
                    .foregroundStyle(
                        state.selectedDeviceDelayOffMinutes > 0
                            ? YeelightDesignTokens.accent
                            : Color.secondary
                    )
                    .frame(width: 18)

                Text("Sleep Timer")
                    .font(.subheadline)

                Spacer(minLength: YeelightDesignTokens.spaceS)

                Text(sleepTimerValue)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, YeelightDesignTokens.spaceXS)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!state.selectedDeviceSupportsSleepTimer || !state.canControlSelectedDevice)
        .help(sleepTimerHelp)
        .accessibilityLabel("Sleep Timer")
        .accessibilityValue(sleepTimerValue)
    }

    private var lightModeControls: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
            Picker("Light mode", selection: Binding(
                get: { state.lightControlMode },
                set: { state.setLightControlMode($0) }
            )) {
                ForEach(LightControlMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(YeelightDesignTokens.accent)
            .disabled(!state.canControlSelectedDevice)

            switch state.lightControlMode {
            case .white:
                whiteTemperatureControl
            case .color:
                colorControl
            case .flow:
                flowControl
            }
        }
        .disabled(!state.canControlSelectedDevice)
    }

    private var whiteTemperatureControl: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            controlSlider(
                title: "White Temperature",
                systemImage: "thermometer.sun",
                value: Binding(
                    get: { state.colorTemperature },
                    set: { state.setColorTemperature($0) }
                ),
                range: 1700...6500,
                valueLabel: "\(Int(state.colorTemperature.rounded()))K"
            )

            HStack {
                Label("Warm", systemImage: "sun.horizon.fill")
                Spacer()
                Label("Cool", systemImage: "snowflake")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            presetStrip(state.whitePresets)
        }
    }

    @ViewBuilder
    private var colorControl: some View {
        if state.showColorControl {
            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
                Button {
                    state.toggleColorEditor()
                } label: {
                    HStack(spacing: YeelightDesignTokens.spaceM) {
                        Circle()
                            .fill(state.selectedColor)
                            .frame(width: 30, height: 30)
                            .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selected color")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text("#\(String(format: "%06X", state.selectedColor.yeelightRGBValue))")
                                .font(.caption.monospacedDigit())
                        }

                        Spacer()

                        Image(systemName: state.isColorEditingActive ? "chevron.up" : "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(YeelightDesignTokens.spaceM)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: YeelightDesignTokens.controlShape)
                .disabled(!state.canControlSelectedDevice || !state.selectedDeviceSupportsColor)

                if state.isColorEditingActive {
                    inlineColorEditor
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                colorPresetStrip(state.colorPresets)
            }
        } else {
            Label("Color controls are hidden in Settings.", systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inlineColorEditor: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            HStack {
                Text("Pick Color")
                    .font(.caption.weight(.semibold))

                Spacer()

                Button("Done") {
                    state.closeColorEditor()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }

            HStack {
                Spacer()
                ColorWheelView(hsv: state.selectedColor.yeelightHSVValue) { hsv in
                    state.setHueSaturation(hue: hsv.hue, saturation: hsv.saturation)
                }
                Spacer()
            }
        }
        .padding(YeelightDesignTokens.spaceM)
        .background(.quaternary, in: YeelightDesignTokens.controlShape)
    }

    private var flowControl: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            HStack {
                Label("Flow", systemImage: "waveform")
                    .font(.caption.weight(.semibold))

                Spacer()

                if state.selectedDeviceIsFlowing {
                    Label("Playing", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(YeelightDesignTokens.accent)
                }
            }

            Picker("Flow", selection: Binding(
                get: { state.selectedFlowPresetID },
                set: { state.setSelectedPresetID($0) }
            )) {
                ForEach(state.flowPresets) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .labelsHidden()
            .disabled(!state.canControlSelectedDevice || !state.selectedDeviceSupportsFlow || state.flowPresets.isEmpty)

            Text(state.selectedFlowPresetSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: YeelightDesignTokens.spaceS) {
                Button {
                    state.applyPreset(id: state.selectedFlowPresetID)
                } label: {
                    Label("Apply", systemImage: "play.fill")
                }
                .yeelightPrimaryButtonStyle()
                .disabled(!state.canControlSelectedDevice || state.flowPresets.isEmpty)

                Button {
                    state.stopFlow()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .disabled(!state.canControlSelectedDevice || !state.selectedDeviceIsFlowing)
            }
            .controlSize(.small)
        }
    }

    private func presetStrip(_ presets: [LightPreset]) -> some View {
        Group {
            if !presets.isEmpty {
                GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64, maximum: 90), spacing: YeelightDesignTokens.spaceS)],
                        alignment: .leading,
                        spacing: YeelightDesignTokens.spaceS
                    ) {
                        ForEach(presets) { preset in
                            Button {
                                state.applyPreset(id: preset.id)
                            } label: {
                                HStack(spacing: YeelightDesignTokens.spaceXS) {
                                    Image(systemName: preset.symbolName)
                                        .font(.caption2)
                                        .frame(width: 12)

                                    Text(preset.title)
                                        .font(.caption2.weight(.medium))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .yeelightGlass(.interactive)
                            .disabled(!state.canControlSelectedDevice)
                            .help(preset.summary)
                        }
                    }
                }
            }
        }
    }

    private func colorPresetStrip(_ presets: [LightPreset]) -> some View {
        Group {
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
                    Text("Quick Colors")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 58), spacing: YeelightDesignTokens.spaceS)],
                        alignment: .leading,
                        spacing: YeelightDesignTokens.spaceS
                    ) {
                        ForEach(presets) { preset in
                            Button {
                                state.applyPreset(id: preset.id)
                            } label: {
                                VStack(spacing: YeelightDesignTokens.spaceXS) {
                                    Circle()
                                        .fill(Color(yeelightRGB: preset.swatchRGB ?? preset.rgb))
                                        .frame(width: 22, height: 22)
                                        .overlay {
                                            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                                        }

                                    Text(preset.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(.quaternary, in: YeelightDesignTokens.controlShape)
                            .disabled(!state.canControlSelectedDevice || !state.selectedDeviceSupportsColor)
                            .help(preset.summary)
                        }
                    }
                }
            }
        }
    }

    private func controlSlider(
        title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            HStack {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                Spacer()
                Text(valueLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: value, in: range)
                .tint(YeelightDesignTokens.accent)
                .disabled(!state.canControlSelectedDevice)
        }
    }

    private var sleepTimerValue: String {
        if !state.selectedDeviceSupportsSleepTimer {
            return "Unsupported"
        }
        if state.selectedDeviceDelayOffMinutes > 0 {
            return state.canControlSelectedDevice
                ? "\(state.selectedDeviceDelayOffMinutes) min"
                : "Last known \(state.selectedDeviceDelayOffMinutes) min"
        }
        return "Set…"
    }

    private var unavailableNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(unavailableTitle)
                    .font(.caption.weight(.semibold))

                Text(unavailableDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: unavailableSymbol)
                .foregroundStyle(YeelightDesignTokens.warning)
        }
        .padding(YeelightDesignTokens.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: YeelightDesignTokens.controlShape)
        .help(unavailableDetail)
        .accessibilityElement(children: .combine)
    }

    private var unavailableTitle: String {
        switch state.status {
        case .searching:
            return "Connecting to light"
        case .error:
            return "Connection failed"
        default:
            return "Light unavailable"
        }
    }

    private var unavailableDetail: String {
        switch state.status {
        case .searching:
            return "Controls will become available when the connection is ready."
        case .error(let message):
            return message
        default:
            return "Controls are disabled. Displayed values are the last known state."
        }
    }

    private var unavailableSymbol: String {
        switch state.status {
        case .searching:
            return "arrow.trianglehead.2.clockwise.rotate.90"
        case .error:
            return "exclamationmark.triangle"
        default:
            return "wifi.slash"
        }
    }

    private var sleepTimerHelp: String {
        if !state.selectedDeviceSupportsSleepTimer {
            return "This light does not advertise sleep timer support."
        }
        if !state.canControlSelectedDevice {
            return "Reconnect to the light to manage its sleep timer."
        }
        return state.selectedDeviceDelayOffMinutes > 0
            ? "Change or cancel the selected light's sleep timer"
            : "Turn off the selected light after a delay"
    }
}
