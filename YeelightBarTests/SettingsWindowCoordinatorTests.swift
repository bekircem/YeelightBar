import AppKit
import XCTest
@testable import YeelightBar

@MainActor
final class SettingsWindowCoordinatorTests: XCTestCase {
    func testRepeatedPresentationRunsOpenActionAndWaitsForAWindowBeforeActivation() {
        var openCount = 0
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            defaults: isolatedDefaults(),
            activateApplication: { activationCount += 1 },
            deferAction: runImmediately
        )

        coordinator.present { openCount += 1 }
        coordinator.present { openCount += 1 }

        XCTAssertEqual(openCount, 2)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(coordinator.presentationRevision, 2)
    }

    func testPendingPresentationFrontsWindowWhenSwiftUIRegistersItLater() {
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            defaults: isolatedDefaults(),
            activateApplication: { activationCount += 1 },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: runImmediately
        )
        let window = RecordingSettingsWindow()

        coordinator.present { }
        coordinator.register(window: window)

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
    }

    func testRegisteringWindowConfiguresItWithoutStealingFocus() {
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            defaults: isolatedDefaults(),
            activateApplication: { activationCount += 1 },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: runImmediately
        )
        let window = RecordingSettingsWindow()
        window.simulatesMiniaturizedState = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        coordinator.register(window: window)

        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(window.deminiaturizeCallCount, 0)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(window.contentMinSize, SettingsWindowGeometry.minimumContentSize)
        XCTAssertEqual(window.title, "YeelightBar Settings")
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.standardWindowButton(.closeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? true)
        XCTAssertFalse(window.standardWindowButton(.zoomButton)?.isHidden ?? true)
    }

    func testRepeatedPresentationReusesRegisteredWindow() {
        let coordinator = SettingsWindowCoordinator(
            defaults: isolatedDefaults(),
            activateApplication: { },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: runImmediately
        )
        let window = RecordingSettingsWindow()
        coordinator.register(window: window)
        window.makeKeyAndOrderFrontCallCount = 0
        var openCount = 0

        coordinator.present { openCount += 1 }
        coordinator.present { openCount += 1 }

        XCTAssertEqual(openCount, 2)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 2)
    }

    func testPresentationRestoresMiniaturizedRegisteredWindow() {
        let coordinator = SettingsWindowCoordinator(
            defaults: migratedDefaults(),
            activateApplication: { },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: runImmediately
        )
        let window = RecordingSettingsWindow()
        coordinator.register(window: window)
        window.simulatesMiniaturizedState = true

        coordinator.present { }

        XCTAssertEqual(window.deminiaturizeCallCount, 1)
        XCTAssertFalse(window.simulatesMiniaturizedState)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
    }

    func testGeometryMigrationRunsOnceAndThenPreservesValidUserFrame() {
        let defaults = isolatedDefaults()
        defaults.set(
            SettingsWindowGeometry.migrationVersion - 1,
            forKey: SettingsWindowGeometry.migrationVersionKey
        )
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let firstCoordinator = SettingsWindowCoordinator(
            defaults: defaults,
            activateApplication: { },
            visibleFrameProvider: { _ in visibleFrame },
            deferAction: runImmediately
        )
        let firstWindow = RecordingSettingsWindow()

        firstCoordinator.register(window: firstWindow)

        XCTAssertEqual(firstWindow.frame.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(firstWindow.frame.midY, visibleFrame.midY, accuracy: 0.001)
        let migratedContentSize = firstWindow.contentRect(forFrameRect: firstWindow.frame).size
        XCTAssertEqual(
            migratedContentSize.width,
            SettingsWindowGeometry.idealContentSize.width,
            accuracy: 0.001
        )
        XCTAssertEqual(
            migratedContentSize.height,
            SettingsWindowGeometry.idealContentSize.height,
            accuracy: 0.001
        )

        let userFrame = NSRect(x: 72, y: 88, width: 800, height: 560)
        let secondCoordinator = SettingsWindowCoordinator(
            defaults: defaults,
            activateApplication: { },
            visibleFrameProvider: { _ in visibleFrame },
            deferAction: runImmediately
        )
        let secondWindow = RecordingSettingsWindow()
        secondWindow.setFrame(userFrame, display: false)

        secondCoordinator.register(window: secondWindow)

        XCTAssertEqual(secondWindow.frame, userFrame)
    }

    func testGeometryMigrationMarkerIsWrittenOnlyAfterDeferredWindowWorkRuns() {
        let defaults = isolatedDefaults()
        defaults.set(
            SettingsWindowGeometry.migrationVersion - 1,
            forKey: SettingsWindowGeometry.migrationVersionKey
        )
        var deferredActions: [@MainActor () -> Void] = []
        let coordinator = SettingsWindowCoordinator(
            defaults: defaults,
            activateApplication: { },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: { action in deferredActions.append(action) }
        )

        coordinator.register(window: RecordingSettingsWindow())

        XCTAssertEqual(
            defaults.integer(forKey: SettingsWindowGeometry.migrationVersionKey),
            SettingsWindowGeometry.migrationVersion - 1
        )

        deferredActions.removeFirst()()

        XCTAssertEqual(
            defaults.integer(forKey: SettingsWindowGeometry.migrationVersionKey),
            SettingsWindowGeometry.migrationVersion
        )
    }

    func testRapidPresentationRequestsOnlyFrontLatestRequest() {
        var deferredActions: [@MainActor () -> Void] = []
        var activationCount = 0
        let coordinator = SettingsWindowCoordinator(
            defaults: migratedDefaults(),
            activateApplication: { activationCount += 1 },
            visibleFrameProvider: { _ in NSRect(x: 0, y: 0, width: 1_200, height: 800) },
            deferAction: { action in deferredActions.append(action) }
        )
        let window = RecordingSettingsWindow()
        coordinator.register(window: window)
        deferredActions.removeAll()

        coordinator.present { }
        coordinator.present { }

        XCTAssertEqual(deferredActions.count, 2)
        deferredActions.removeFirst()()
        deferredActions.removeFirst()()

        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(window.makeKeyAndOrderFrontCallCount, 1)
    }

    func testFittedFramePreservesFrameAlreadyInsideSafeArea() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_200, height: 800)
        let frame = NSRect(x: 100, y: 80, width: 880, height: 620)

        let result = SettingsWindowGeometry.fittedFrame(frame, in: visibleFrame)

        XCTAssertEqual(result, frame)
    }

    func testFittedFrameClampsOversizedAndOffscreenWindow() {
        let visibleFrame = NSRect(x: 0, y: 40, width: 1_000, height: 700)
        let frame = NSRect(x: -500, y: -300, width: 1_400, height: 900)

        let result = SettingsWindowGeometry.fittedFrame(frame, in: visibleFrame)

        XCTAssertEqual(result, NSRect(x: 24, y: 64, width: 952, height: 652))
    }

    func testCenteredFrameSupportsDisplaysWithNegativeCoordinates() {
        let visibleFrame = NSRect(x: -1_440, y: 25, width: 1_440, height: 875)

        let result = SettingsWindowGeometry.centeredFrame(
            size: NSSize(width: 880, height: 648),
            in: visibleFrame
        )

        XCTAssertEqual(result.midX, visibleFrame.midX, accuracy: 0.001)
        XCTAssertEqual(result.midY, visibleFrame.midY, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(result.minX, visibleFrame.minX + 24)
        XCTAssertLessThanOrEqual(result.maxX, visibleFrame.maxX - 24)
    }

    func testTinyDisplayStillProducesPositiveFrame() {
        let visibleFrame = NSRect(x: 10, y: 20, width: 30, height: 30)

        let result = SettingsWindowGeometry.centeredFrame(
            size: NSSize(width: 880, height: 620),
            in: visibleFrame
        )

        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
        XCTAssertTrue(visibleFrame.contains(result))
    }

    func testIdealWindowFitsWithinEightyFivePercentOfReferenceDisplay() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
        let idealWindowSize = NSSize(
            width: SettingsWindowGeometry.idealContentSize.width,
            height: SettingsWindowGeometry.idealContentSize.height + 28
        )
        let result = SettingsWindowGeometry.centeredFrame(size: idealWindowSize, in: visibleFrame)

        XCTAssertLessThanOrEqual(result.width / visibleFrame.width, 0.85)
        XCTAssertLessThanOrEqual(result.height / visibleFrame.height, 0.85)
    }

    func testMinimumContentSizeAdaptsToAConstrainedVisibleFrame() {
        let visibleFrame = NSRect(x: 0, y: 0, width: 600, height: 420)
        let coordinator = SettingsWindowCoordinator(
            defaults: migratedDefaults(),
            activateApplication: { },
            visibleFrameProvider: { _ in visibleFrame },
            deferAction: runImmediately
        )
        let window = RecordingSettingsWindow()

        coordinator.register(window: window)

        XCTAssertGreaterThan(window.contentMinSize.width, 0)
        XCTAssertGreaterThan(window.contentMinSize.height, 0)
        XCTAssertLessThan(window.contentMinSize.width, SettingsWindowGeometry.minimumContentSize.width)
        XCTAssertLessThan(window.contentMinSize.height, SettingsWindowGeometry.minimumContentSize.height)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "SettingsWindowCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func migratedDefaults() -> UserDefaults {
        let defaults = isolatedDefaults()
        defaults.set(
            SettingsWindowGeometry.migrationVersion,
            forKey: SettingsWindowGeometry.migrationVersionKey
        )
        return defaults
    }

    private func runImmediately(_ action: @escaping @MainActor () -> Void) {
        action()
    }
}

@MainActor
private final class RecordingSettingsWindow: NSWindow {
    var simulatesMiniaturizedState = false
    var deminiaturizeCallCount = 0
    var makeKeyAndOrderFrontCallCount = 0

    init() {
        super.init(
            contentRect: NSRect(x: 100, y: 100, width: 880, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    override var isMiniaturized: Bool {
        simulatesMiniaturizedState
    }

    override func deminiaturize(_ sender: Any?) {
        deminiaturizeCallCount += 1
        simulatesMiniaturizedState = false
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        makeKeyAndOrderFrontCallCount += 1
    }
}
