import Sparkle

@MainActor
protocol UpdateChecking {
    func checkForUpdates()
}

@MainActor
struct DisabledUpdateChecker: UpdateChecking {
    func checkForUpdates() {}
}

@MainActor
final class SparkleUpdateController: UpdateChecking {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
