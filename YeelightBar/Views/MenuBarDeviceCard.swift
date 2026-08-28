import SwiftUI

struct MenuBarDeviceCard<ExpandedContent: View>: View {
    let snapshot: DeviceCardSnapshot
    let selectedStatusTitle: String?
    let showsEndpoint: Bool
    let reduceMotion: Bool
    let glassNamespace: Namespace.ID
    let onSelect: () -> Void
    @ViewBuilder let expandedContent: ExpandedContent

    init(
        snapshot: DeviceCardSnapshot,
        selectedStatusTitle: String?,
        showsEndpoint: Bool,
        reduceMotion: Bool,
        glassNamespace: Namespace.ID,
        onSelect: @escaping () -> Void,
        @ViewBuilder expandedContent: () -> ExpandedContent
    ) {
        self.snapshot = snapshot
        self.selectedStatusTitle = selectedStatusTitle
        self.showsEndpoint = showsEndpoint
        self.reduceMotion = reduceMotion
        self.glassNamespace = glassNamespace
        self.onSelect = onSelect
        self.expandedContent = expandedContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            Button(action: onSelect) {
                HStack(spacing: YeelightDesignTokens.spaceM) {
                    deviceIcon

                    VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
                        HStack(spacing: YeelightDesignTokens.spaceS) {
                            Text(snapshot.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if snapshot.isSelected {
                                Text("ACTIVE")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(YeelightDesignTokens.accent)
                            }
                        }

                        HStack(spacing: 6) {
                            Circle()
                                .fill(snapshot.statusColor)
                                .frame(width: 6, height: 6)

                            Text(statusTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                        }
                    }

                    Spacer(minLength: YeelightDesignTokens.spaceS)

                    Image(systemName: snapshot.isSelected ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(snapshot.isSelected ? snapshot.name : "Control \(snapshot.name)")
            .accessibilityLabel(snapshot.name)
            .accessibilityValue(statusTitle)
            .accessibilityHint(snapshot.isSelected ? "Expanded light controls" : "Select and expand light controls")

            if snapshot.isSelected {
                if showsEndpoint {
                    HStack(spacing: YeelightDesignTokens.spaceS) {
                        if !snapshot.model.isEmpty {
                            Text(snapshot.model)
                                .lineLimit(1)

                            Text("·")
                                .accessibilityHidden(true)
                        }

                        Text(snapshot.endpoint)
                            .monospaced()
                            .textSelection(.enabled)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Divider()
                    .opacity(0.55)

                expandedContent
            }
        }
        .padding(YeelightDesignTokens.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yeelightGlass(snapshot.isSelected ? .tinted(snapshot.ambientColor) : .interactive)
        .glassEffectID(snapshot.id, in: glassNamespace)
        .matchedGlassTransition(enabled: !reduceMotion)
        .accessibilityElement(children: .contain)
    }

    private var statusTitle: String {
        if snapshot.isSelected, let selectedStatusTitle {
            return selectedStatusTitle
        }
        return snapshot.statusTitle
    }

    private var deviceIcon: some View {
        ZStack {
            Circle()
                .fill(snapshot.ambientColor.opacity(snapshot.isSelected ? 0.28 : 0.14))

            Image(systemName: snapshot.power == .on ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(snapshot.isSelected ? snapshot.ambientColor : Color.secondary)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

private extension View {
    @ViewBuilder
    func matchedGlassTransition(enabled: Bool) -> some View {
        if enabled {
            glassEffectTransition(.matchedGeometry)
        } else {
            self
        }
    }
}
