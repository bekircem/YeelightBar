import Foundation
import SwiftUI

struct ModePresetDetailPane: View {
    let preset: LightPreset
    let isFavorite: Bool
    let canApply: Bool
    let onToggleFavorite: () -> Void
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ambientPreview
                primaryActions
                metadataCard

                if preset.kind == .flow {
                    flowSequenceCard
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ambientPreview: some View {
        GlassSection(style: .tinted(presetAccentColor)) {
            detailHeader
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                largeIcon

                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        DetailBadge(text: preset.kind.title)
                        DetailBadge(text: preset.isBuiltIn ? "Built-in" : "Custom")
                    }
                }

                Spacer(minLength: 0)

                if !preset.isBuiltIn {
                    Menu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete \(preset.title)", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("More actions for \(preset.title)")
                }
            }

            Text(preset.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryActions: some View {
        GlassEffectContainer(spacing: YeelightDesignTokens.spaceS) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: YeelightDesignTokens.spaceS) {
                    applyButton
                    favoriteButton
                }

                VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
                    applyButton
                    favoriteButton
                }
            }
        }
    }

    private var applyButton: some View {
        Button(action: onApply) {
            Label("Apply", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .yeelightPrimaryButtonStyle()
        .disabled(!canApply)
        .help(canApply ? "Apply \(preset.title)" : "Select an online bulb before applying")
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Label(isFavorite ? "Favorited" : "Favorite", systemImage: isFavorite ? "star.fill" : "star")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")
    }

    private var metadataCard: some View {
        DetailCard(title: preset.kind == .flow ? "Flow Details" : "Look Details") {
            switch preset.kind {
            case .color:
                DetailInfoRow(label: "Color", value: "#\(String(format: "%06X", preset.rgb))")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .colorTemperature:
                DetailInfoRow(label: "Temperature", value: "\(preset.colorTemperature)K")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .hsv:
                DetailInfoRow(label: "Hue", value: "\(preset.hue)°")
                DetailInfoRow(label: "Saturation", value: "\(preset.saturation)%")
                DetailInfoRow(label: "Brightness", value: "\(preset.brightness)%")
            case .flow:
                if let flow = preset.flow {
                    DetailInfoRow(label: "Steps", value: "\(flow.steps.count)")
                    DetailInfoRow(label: "Playback", value: playbackText(for: flow))
                    DetailInfoRow(label: "When Finished", value: flow.stopAction.editorTitle)
                } else {
                    Text("This flow is missing its step data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var flowSequenceCard: some View {
        if let flow = preset.flow {
            DetailCard(title: "Step Sequence") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(flow.steps.enumerated()), id: \.element.id) { index, step in
                        FlowStepSummaryRow(index: index, step: step)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var largeIcon: some View {
        if let rgb = preset.swatchRGB {
            Circle()
                .fill(Color(yeelightRGB: rgb))
                .frame(width: 44, height: 44)
                .overlay {
                    Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: preset.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func playbackText(for flow: ColorFlow) -> String {
        if flow.count == 0 {
            return "Repeats forever"
        }

        guard !flow.steps.isEmpty else {
            return "\(flow.count) transitions"
        }

        if flow.count.isMultiple(of: flow.steps.count) {
            let cycles = flow.count / flow.steps.count
            return "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
        }

        return "\(flow.count) transitions"
    }

    private var presetAccentColor: Color {
        if let rgb = preset.swatchRGB {
            return Color(yeelightRGB: rgb)
        }
        return YeelightDesignTokens.accent
    }
}

struct ModeLibraryEmptyDetail: View {
    let filter: ModeLibraryFilter

    var body: some View {
        ContentUnavailableView {
            Label("Select a \(filter.selectionNoun)", systemImage: "sidebar.right")
        } description: {
            Text("Choose an item in the library to inspect details and manage actions.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DetailCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.vertical, YeelightDesignTokens.spaceXS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}

struct DetailBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

struct FlowStepSummaryRow: View {
    let index: Int
    let step: FlowStep

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .trailing)

            stepIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(step.mode.editorTitle)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.mode {
        case .color:
            Circle()
                .fill(Color(yeelightRGB: step.rgb))
                .frame(width: 16, height: 16)
                .overlay { Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1) }
        case .colorTemperature:
            Image(systemName: "thermometer.sun")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        case .sleep:
            Image(systemName: "pause.fill")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }

    private var detail: String {
        let duration = formattedMilliseconds(step.duration)

        switch step.mode {
        case .color:
            return "#\(String(format: "%06X", step.rgb)) · \(duration) · \(brightnessText)"
        case .colorTemperature:
            return "\(step.colorTemperature)K · \(duration) · \(brightnessText)"
        case .sleep:
            return duration
        }
    }

    private var brightnessText: String {
        step.brightness.map { "\($0)%" } ?? "current brightness"
    }
}
