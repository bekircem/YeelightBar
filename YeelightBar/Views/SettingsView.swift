import Foundation
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject private var settingsWindowCoordinator: SettingsWindowCoordinator
    @SceneStorage("settings.selectedPanel") private var selectedPanelRawValue = SettingsPanel.general.rawValue
    @State var confirmForgetDevices = false
    @State var confirmResetPreferences = false
    @State var recordingShortcutAction: KeyboardShortcutAction?
    @State var recordingPresetShortcutID: UUID?

    private var selectedPanel: SettingsPanel {
        SettingsSelection.panel(for: selectedPanelRawValue)
    }

    private var selectedPanelBinding: Binding<SettingsPanel?> {
        Binding(
            get: { selectedPanel },
            set: { panel in
                selectedPanelRawValue = SettingsSelection.rawValue(for: panel)
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            detail
        }
        .background {
            SettingsWindowReader { window in
                settingsWindowCoordinator.register(window: window)
            }
            .frame(width: 0, height: 0)
        }
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
        List(selection: selectedPanelBinding) {
            ForEach(SettingsPanel.allCases) { panel in
                Label {
                    Text(panel.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: panel.systemImage)
                        .frame(width: SettingsLayout.sidebarIconWidth)
                }
                    .lineLimit(1)
                    .tag(panel)
                    .accessibilityIdentifier("settings.sidebar.\(panel.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .frame(width: SettingsLayout.sidebarWidth)
        .accessibilityIdentifier("settings.sidebar")
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
            .accessibilityIdentifier("settings.detail.\(selectedPanel.rawValue)")
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
            .accessibilityIdentifier("settings.detail.\(selectedPanel.rawValue)")
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
}

enum SettingsSelection {
    static func panel(for rawValue: String) -> SettingsPanel {
        SettingsPanel(rawValue: rawValue) ?? .general
    }

    static func rawValue(for panel: SettingsPanel?) -> String {
        (panel ?? .general).rawValue
    }
}

enum SettingsLayout {
    static let sidebarWidth: CGFloat = 216
    static let sidebarIconWidth: CGFloat = 18
}
