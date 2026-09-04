import Dispatch
import SwiftUI

@main
enum YeelightBarMain {
    static func main() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            YeelightBarTestApp.main()
        } else {
            YeelightBarApp.main()
        }
    }
}

private struct YeelightBarApp: App {
    private let updateController: SparkleUpdateController
    @StateObject private var state: AppState
    @StateObject private var settingsWindowCoordinator: SettingsWindowCoordinator

    init() {
        let updateController = SparkleUpdateController()
        self.updateController = updateController

        let state = AppState(updateChecker: updateController)
        _state = StateObject(wrappedValue: state)
        _settingsWindowCoordinator = StateObject(wrappedValue: SettingsWindowCoordinator())

        DispatchQueue.main.async { [state] in
            state.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
                .environmentObject(settingsWindowCoordinator)
        } label: {
            Image(systemName: state.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(settingsWindowCoordinator)
        }
        .defaultSize(
            width: SettingsWindowGeometry.idealContentSize.width,
            height: SettingsWindowGeometry.idealContentSize.height
        )
        .windowResizability(.contentMinSize)
    }
}

private struct YeelightBarTestApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
