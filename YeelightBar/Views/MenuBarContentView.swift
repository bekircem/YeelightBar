import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var deviceGlassNamespace

    private var deviceSnapshots: [DeviceCardSnapshot] {
        state.devices.map {
            DeviceCardSnapshot(device: $0, selectedDeviceID: state.selectedDeviceID)
        }
    }

    private var onlineDeviceCount: Int {
        state.devices.filter(\.state.online).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, YeelightDesignTokens.spaceL)
                .padding(.vertical, YeelightDesignTokens.spaceS)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
                    if state.devices.isEmpty {
                        emptyState
                    } else {
                        deviceCards
                        quickScenes
                    }
                }
                .padding(YeelightDesignTokens.spaceM)
            }
            .frame(height: scrollViewportHeight)
            .scrollBounceBehavior(.basedOnSize)

            Divider()

            footer
                .padding(.horizontal, YeelightDesignTokens.spaceL)
                .padding(.vertical, YeelightDesignTokens.spaceS)
        }
        .frame(width: state.popoverWidth)
    }

    private var header: some View {
        HStack(spacing: YeelightDesignTokens.spaceM) {
            ZStack {
                Circle()
                    .fill(YeelightDesignTokens.accent.opacity(0.18))

                Image(systemName: state.menuBarSymbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(YeelightDesignTokens.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("YeelightBar")
                    .font(.subheadline.weight(.semibold))

                Text(deviceSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.discover()
            } label: {
                Group {
                    if isDiscovering {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .disabled(isDiscovering)
            .help(isDiscovering ? "Discovering devices" : "Discover devices")
            .accessibilityLabel(isDiscovering ? "Discovering devices" : "Discover devices")
        }
    }

    private var deviceCards: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
            Text("LIGHTS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            GlassEffectContainer(spacing: YeelightDesignTokens.spaceM) {
                VStack(spacing: YeelightDesignTokens.spaceM) {
                    ForEach(deviceSnapshots) { snapshot in
                        MenuBarDeviceCard(
                            snapshot: snapshot,
                            selectedStatusTitle: selectedStatusOverride,
                            showsEndpoint: state.controlDisplayMode == .detailed,
                            reduceMotion: reduceMotion,
                            glassNamespace: deviceGlassNamespace,
                            onSelect: { selectDevice(snapshot.id) }
                        ) {
                            if snapshot.isSelected {
                                MenuBarLightControls()
                                    .environmentObject(state)
                            }
                        }
                    }
                }
            }
        }
    }

    private var quickScenes: some View {
        MenuBarQuickScenes(
            presets: state.favoritePresets,
            displayMode: state.controlDisplayMode,
            isEnabled: state.canControlSelectedDevice,
            onApply: { state.applyPreset(id: $0) }
        )
    }

    private var emptyState: some View {
        GlassSection(style: .tinted(YeelightDesignTokens.accent)) {
            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
                Label(state.status.title, systemImage: state.status.symbolName)
                    .font(.headline)

                Text("Discover a Yeelight LAN-compatible light, then approve it before YeelightBar connects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !state.discoveredCandidates.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceS) {
                        Text("DISCOVERED LIGHTS")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)

                        ForEach(state.discoveredCandidates.prefix(3)) { candidate in
                            discoveryCandidateRow(candidate)
                        }
                    }
                }

                HStack(spacing: YeelightDesignTokens.spaceS) {
                    Button {
                        state.discover()
                    } label: {
                        Label("Discover", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .yeelightPrimaryButtonStyle()

                    SettingsPresentationButton {
                        Label("Device Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.small)
            }
        }
    }

    private func discoveryCandidateRow(_ candidate: DiscoveryCandidate) -> some View {
        HStack(spacing: YeelightDesignTokens.spaceS) {
            Image(systemName: candidate.endpointChanged ? "exclamationmark.triangle" : "lightbulb")
                .foregroundStyle(candidate.endpointChanged ? YeelightDesignTokens.warning : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.device.displayName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text("\(candidate.device.host):\(candidate.device.port)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(candidate.endpointChanged ? "Approve" : "Add") {
                state.trustDiscoveredCandidate(id: candidate.id)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var footer: some View {
        HStack(spacing: YeelightDesignTokens.spaceS) {
            SettingsPresentationButton {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle)

            Spacer()

            Button {
                state.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle)
        }
        .controlSize(.small)
    }

    private var deviceSummary: String {
        guard !state.devices.isEmpty else {
            return "No lights configured"
        }

        let lightNoun = state.devices.count == 1 ? "light" : "lights"
        return "\(state.devices.count) \(lightNoun) · \(onlineDeviceCount) online"
    }

    private var isDiscovering: Bool {
        state.status == .searching
    }

    private var scrollViewportHeight: CGFloat {
        if state.devices.isEmpty {
            return 260
        }

        switch state.controlDisplayMode {
        case .compact:
            return 380
        case .detailed:
            return 520
        }
    }

    private var selectedStatusOverride: String? {
        switch state.status {
        case .idle, .connected:
            return nil
        case .searching:
            return "Connecting…"
        case .offline:
            return "Offline"
        case .notFound:
            return "LAN Control unavailable"
        case .error:
            return "Connection error"
        }
    }

    private func selectDevice(_ id: String) {
        let animation: Animation? = reduceMotion
            ? nil
            : .snappy(duration: 0.24, extraBounce: 0.06)

        withAnimation(animation) {
            state.selectDevice(id: id)
        }
    }
}
