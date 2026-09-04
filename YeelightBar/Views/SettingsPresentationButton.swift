import SwiftUI

struct SettingsPresentationButton<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var coordinator: SettingsWindowCoordinator

    private let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Button {
            coordinator.present {
                openSettings()
            }
        } label: {
            label()
        }
    }
}
