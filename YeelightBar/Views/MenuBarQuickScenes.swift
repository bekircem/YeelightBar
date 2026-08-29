import SwiftUI

enum QuickScenePresentation {
    static func visiblePresets(
        from presets: [LightPreset],
        displayMode: ControlDisplayMode
    ) -> [LightPreset] {
        switch displayMode {
        case .detailed:
            return presets
        case .compact:
            return Array(presets.prefix(3))
        }
    }
}

struct MenuBarQuickScenes: View {
    let presets: [LightPreset]
    let displayMode: ControlDisplayMode
    let isEnabled: Bool
    let onApply: (String) -> Void

    private var visiblePresets: [LightPreset] {
        QuickScenePresentation.visiblePresets(from: presets, displayMode: displayMode)
    }

    private var primaryPresets: [LightPreset] {
        Array(visiblePresets.prefix(3))
    }

    private var overflowPresets: [LightPreset] {
        Array(visiblePresets.dropFirst(3))
    }

    var body: some View {
        if !visiblePresets.isEmpty {
            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
                HStack(spacing: YeelightDesignTokens.spaceS) {
                    Text("QUICK SCENES")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !overflowPresets.isEmpty {
                        Menu("\(overflowPresets.count) more") {
                            ForEach(overflowPresets) { preset in
                                Button {
                                    onApply(preset.id)
                                } label: {
                                    Label(preset.title, systemImage: preset.symbolName)
                                }
                                .disabled(!isEnabled)
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .controlSize(.mini)
                        .fixedSize()
                        .accessibilityLabel("More quick scenes")
                    }
                }

                GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 92, maximum: 116), spacing: YeelightDesignTokens.spaceS)],
                        alignment: .leading,
                        spacing: YeelightDesignTokens.spaceS
                    ) {
                        ForEach(primaryPresets) { preset in
                            sceneButton(preset)
                        }
                    }
                }
            }
        }
    }

    private func sceneButton(_ preset: LightPreset) -> some View {
        Button {
            onApply(preset.id)
        } label: {
            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
                presetIcon(preset)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(sceneValue(preset))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(YeelightDesignTokens.spaceS)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .yeelightGlass(.interactive)
        .disabled(!isEnabled)
        .help(preset.summary)
        .accessibilityLabel("Apply \(preset.title)")
        .accessibilityValue(sceneValue(preset))
        .accessibilityHint(isEnabled ? "Applies this scene to the selected light" : "Reconnect the selected light to apply scenes")
    }

    @ViewBuilder
    private func presetIcon(_ preset: LightPreset) -> some View {
        if let rgb = preset.swatchRGB {
            Circle()
                .fill(Color(yeelightRGB: rgb))
                .frame(width: 24, height: 24)
                .overlay { Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1) }
        } else if preset.kind == .colorTemperature {
            Image(systemName: "thermometer.sun.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(
                    LightAppearanceColorResolver.temperatureColor(kelvin: preset.colorTemperature)
                )
                .frame(width: 24, height: 24)
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(YeelightDesignTokens.accent)
                .frame(width: 24, height: 24)
        }
    }

    private func sceneValue(_ preset: LightPreset) -> String {
        switch preset.kind {
        case .colorTemperature:
            return "\(preset.colorTemperature)K · \(preset.brightness)%"
        case .color, .hsv:
            return "\(preset.brightness)%"
        case .flow:
            return "Flow"
        }
    }
}
