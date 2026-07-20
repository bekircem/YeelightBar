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
    @StateObject private var state: AppState

    init() {
        let state = AppState()
        _state = StateObject(wrappedValue: state)

        DispatchQueue.main.async { [state] in
            state.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct YeelightBarTestApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
