import XCTest
import SwiftUI
@testable import YeelightBar

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testDecodesLegacyPreferencesWithNewDefaults() throws {
        let legacyJSON = """
        {
          "savedDevices": [],
          "transitionDuration": 250,
          "discoveryRetryInterval": 20,
          "launchAtLogin": true
        }
        """

        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(preferences.transitionDuration, 250)
        XCTAssertEqual(preferences.discoveryRetryInterval, 20)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertEqual(preferences.menuBarIconStyle, .connectionStatus)
        XCTAssertEqual(preferences.defaultManualPort, 55443)
        XCTAssertEqual(preferences.commandTimeout, 5)
        XCTAssertEqual(preferences.reconnectInterval, 2)
        XCTAssertEqual(preferences.brightnessDebounceMilliseconds, 180)
        XCTAssertEqual(preferences.colorDebounceMilliseconds, 180)
        XCTAssertEqual(preferences.popoverWidth, 340)
        XCTAssertEqual(preferences.controlDisplayMode, .detailed)
        XCTAssertTrue(preferences.showColorControl)
        XCTAssertEqual(preferences.customPresets, [])
        XCTAssertEqual(preferences.favoritePresetIDs, LightPreset.defaultFavoriteIDs)
        XCTAssertEqual(preferences.selectedPresetID, LightPreset.reading.id)
        XCTAssertTrue(preferences.shortcutsEnabled)
        XCTAssertEqual(preferences.keyboardShortcuts, ConfiguredShortcut.defaultSet)
        XCTAssertEqual(preferences.presetShortcuts, [])
        XCTAssertEqual(preferences.shortcutBrightnessStep, 10)
    }

    func testSettingsSettersClampAndPersistValues() {
        let store = makeIsolatedStore()
        let state = AppState(store: store)

        state.setCommandTimeout(0.2)
        state.setReconnectInterval(100)
        state.setBrightnessDebounceMilliseconds(2)
        state.setColorDebounceMilliseconds(2_000)
        state.setPopoverWidth(900)
        state.setDefaultManualPort(12345)
        state.setMenuBarIconStyle(.filled)
        state.setControlDisplayMode(.compact)
        state.setShowColorControl(false)
        state.setShortcutsEnabled(false)
        state.setShortcutBrightnessStep(100)

        let preferences = store.load()

        XCTAssertEqual(preferences.commandTimeout, 1)
        XCTAssertEqual(preferences.reconnectInterval, 60)
        XCTAssertEqual(preferences.brightnessDebounceMilliseconds, 30)
        XCTAssertEqual(preferences.colorDebounceMilliseconds, 1000)
        XCTAssertEqual(preferences.popoverWidth, 520)
        XCTAssertEqual(preferences.defaultManualPort, 12345)
        XCTAssertEqual(preferences.menuBarIconStyle, .filled)
        XCTAssertEqual(preferences.controlDisplayMode, .compact)
        XCTAssertFalse(preferences.showColorControl)
        XCTAssertFalse(preferences.shortcutsEnabled)
        XCTAssertEqual(preferences.shortcutBrightnessStep, 25)
    }

    func testResetPreferencesClearsStoredDevices() {
        let store = makeIsolatedStore()
        let device = YeelightDevice(
            id: "stored",
            name: "Stored",
            model: "color",
            host: "192.168.1.50",
            port: 55443,
            capabilities: ["get_prop"],
            state: .unknown,
            lastSeen: Date(timeIntervalSince1970: 0)
        )

        store.save(AppPreferences(
            savedDevices: [device],
            selectedDeviceID: device.id,
            transitionDuration: 1000,
            discoveryRetryInterval: 30,
            launchAtLogin: false,
            menuBarIconStyle: .filled,
            defaultManualPort: 12345,
            commandTimeout: 8,
            reconnectInterval: 5,
            brightnessDebounceMilliseconds: 250,
            colorDebounceMilliseconds: 300,
            popoverWidth: 400,
            controlDisplayMode: .compact,
            showColorControl: false,
            debugLoggingEnabled: true,
            customPresets: [
                LightPreset(id: "custom", title: "Custom", kind: .color, brightness: 60, rgb: 0xFF0000)
            ],
            favoritePresetIDs: ["custom"],
            selectedPresetID: "custom",
            shortcutsEnabled: false,
            keyboardShortcuts: [],
            presetShortcuts: [
                PresetShortcut(
                    presetID: "custom",
                    combination: HotKeyCombination(keyCode: 8, modifiers: [.control, .option, .command], keyLabel: "C"),
                    isEnabled: true
                )
            ],
            shortcutBrightnessStep: 3
        ))

        let state = AppState(store: store)
        state.resetPreferences()

        let preferences = store.load()

        XCTAssertTrue(preferences.savedDevices.isEmpty)
        XCTAssertNil(preferences.selectedDeviceID)
        XCTAssertEqual(preferences.transitionDuration, AppPreferences.defaults.transitionDuration)
        XCTAssertEqual(preferences.defaultManualPort, AppPreferences.defaults.defaultManualPort)
        XCTAssertEqual(preferences.customPresets, [])
        XCTAssertEqual(preferences.favoritePresetIDs, LightPreset.defaultFavoriteIDs)
        XCTAssertEqual(preferences.selectedPresetID, LightPreset.reading.id)
        XCTAssertTrue(preferences.shortcutsEnabled)
        XCTAssertEqual(preferences.keyboardShortcuts, ConfiguredShortcut.defaultSet)
        XCTAssertEqual(preferences.presetShortcuts, [])
        XCTAssertEqual(preferences.shortcutBrightnessStep, 10)
        XCTAssertEqual(state.manualPort, String(AppPreferences.defaults.defaultManualPort))
    }

    func testPresetFiltersSeparateWhiteColorAndFlowModes() {
        let store = makeIsolatedStore()
        let state = AppState(store: store)

        XCTAssertFalse(state.whitePresets.isEmpty)
        XCTAssertFalse(state.colorPresets.isEmpty)
        XCTAssertFalse(state.flowPresets.isEmpty)
        XCTAssertTrue(state.whitePresets.allSatisfy { $0.kind == .colorTemperature })
        XCTAssertTrue(state.colorPresets.allSatisfy { $0.kind == .color || $0.kind == .hsv })
        XCTAssertTrue(state.flowPresets.allSatisfy { $0.kind == .flow })
    }

    func testBuiltInColorPresetsIncludeStaticColors() {
        let colorPresetIDs = Set(LightPreset.builtIns.filter { $0.kind == .color }.map(\.id))

        XCTAssertTrue(colorPresetIDs.contains(LightPreset.movie.id))
        XCTAssertTrue(colorPresetIDs.contains(LightPreset.warmAmber.id))
        XCTAssertTrue(colorPresetIDs.contains(LightPreset.aqua.id))
        XCTAssertTrue(colorPresetIDs.contains(LightPreset.rose.id))
        XCTAssertTrue(colorPresetIDs.contains(LightPreset.blue.id))
    }

    func testSaveCurrentModeCapturesRGBHSVAndTemperatureLooks() {
        let store = makeIsolatedStore()
        let state = AppState(store: store)
        let device = makeDevice(state: DeviceState(
            brightness: 64,
            rgb: 0x112233,
            colorMode: .rgb,
            online: true
        ))
        state.devices = [device]
        state.selectedDeviceID = device.id

        state.brightness = 64
        state.selectedColor = Color(yeelightRGB: 0x112233)
        let rgbPreset = state.saveCurrentMode(named: "  RGB Look  ")

        XCTAssertEqual(rgbPreset?.title, "RGB Look")
        XCTAssertEqual(rgbPreset?.kind, .color)
        XCTAssertEqual(rgbPreset?.rgb, 0x112233)
        XCTAssertEqual(rgbPreset?.brightness, 64)

        state.devices[0].state.colorMode = .hsv
        state.devices[0].state.hue = 210
        state.devices[0].state.saturation = 65
        state.brightness = 42
        let hsvPreset = state.saveCurrentMode(named: "HSV Look")

        XCTAssertEqual(hsvPreset?.kind, .hsv)
        XCTAssertEqual(hsvPreset?.hue, 210)
        XCTAssertEqual(hsvPreset?.saturation, 65)
        XCTAssertEqual(hsvPreset?.brightness, 42)

        state.devices[0].state.colorMode = .colorTemperature
        state.colorTemperature = 2850
        state.brightness = 31
        let temperaturePreset = state.saveCurrentMode(named: "Warm Look")

        XCTAssertEqual(temperaturePreset?.kind, .colorTemperature)
        XCTAssertEqual(temperaturePreset?.colorTemperature, 2850)
        XCTAssertEqual(temperaturePreset?.brightness, 31)

        let savedPresets = store.load().customPresets
        XCTAssertEqual(savedPresets.count, 3)
        XCTAssertEqual(savedPresets.first { $0.title == "RGB Look" }?.rgb, 0x112233)
        XCTAssertEqual(savedPresets.first { $0.title == "HSV Look" }?.hue, 210)
        XCTAssertEqual(savedPresets.first { $0.title == "Warm Look" }?.colorTemperature, 2850)
    }

    func testSaveCurrentModeRequiresSelectedDevice() {
        let store = makeIsolatedStore()
        let state = AppState(store: store)

        XCTAssertNil(state.currentLightLook)
        XCTAssertNil(state.saveCurrentMode(named: "Should Not Save"))
        XCTAssertTrue(state.customPresets.isEmpty)
        XCTAssertTrue(store.load().customPresets.isEmpty)
    }

    func testSaveCustomFlowReturnsCreatedPresetOnlyForValidInput() {
        let store = makeIsolatedStore()
        let state = AppState(store: store)

        XCTAssertNil(state.saveCustomFlow(
            named: "Empty",
            flow: ColorFlow(count: 0, steps: [])
        ))

        let flow = ColorFlow(
            count: 6,
            stopAction: .stay,
            steps: [
                .color(0xFF0000, brightness: 80, duration: 500),
                .sleep(500)
            ]
        )
        let preset = state.saveCustomFlow(named: "  Evening Pulse  ", flow: flow)

        XCTAssertEqual(preset?.title, "Evening Pulse")
        XCTAssertEqual(preset?.kind, .flow)
        XCTAssertEqual(preset?.flow, flow)
        XCTAssertEqual(state.selectedPresetID, preset?.id)
        XCTAssertEqual(store.load().customPresets, [preset].compactMap { $0 })
    }

    func testPreferenceSaveSchedulerCoalescesDeferredSaves() async {
        var savedPreferences: [AppPreferences] = []
        let scheduler = PreferenceSaveScheduler(delay: 0.05) { preferences in
            savedPreferences.append(preferences)
        }

        var first = AppPreferences.defaults
        first.commandTimeout = 3
        var second = AppPreferences.defaults
        second.commandTimeout = 9

        scheduler.schedule(first)
        scheduler.schedule(second)

        XCTAssertTrue(savedPreferences.isEmpty)

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(savedPreferences.count, 1)
        XCTAssertEqual(savedPreferences.first?.commandTimeout, 9)
    }

    func testPreferenceSaveSchedulerFlushCancelsPendingSave() async {
        var savedPreferences: [AppPreferences] = []
        let scheduler = PreferenceSaveScheduler(delay: 0.1) { preferences in
            savedPreferences.append(preferences)
        }

        var deferred = AppPreferences.defaults
        deferred.commandTimeout = 4
        var immediate = AppPreferences.defaults
        immediate.commandTimeout = 7

        scheduler.schedule(deferred)
        scheduler.flush(immediate)

        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(savedPreferences.count, 1)
        XCTAssertEqual(savedPreferences.first?.commandTimeout, 7)
    }

    func testDiscoveryRetryBacksOffWhileConnected() {
        XCTAssertEqual(AppState.effectiveDiscoveryRetryInterval(baseInterval: 15, connected: false), 15)
        XCTAssertEqual(AppState.effectiveDiscoveryRetryInterval(baseInterval: 15, connected: true), 60)
        XCTAssertEqual(AppState.effectiveDiscoveryRetryInterval(baseInterval: 90, connected: true), 90)
    }

    func testImportRejectsOversizedAndAdversarialCollections() throws {
        let state = AppState(store: makeIsolatedStore())

        XCTAssertThrowsError(try state.applyImportedPreferences(Data(repeating: 0, count: 5 * 1024 * 1024 + 1))) { error in
            XCTAssertEqual(error as? PreferencesImportError, .fileTooLarge)
        }

        var preferences = AppPreferences.defaults
        preferences.savedDevices = (0...100).map { index in
            YeelightDevice(
                id: "device-\(index)",
                name: "Device",
                model: "color",
                host: "192.168.1.\((index % 250) + 1)",
                port: 55443,
                capabilities: [],
                state: .unknown,
                lastSeen: .distantPast
            )
        }

        XCTAssertThrowsError(try state.applyImportedPreferences(JSONEncoder().encode(preferences))) { error in
            XCTAssertEqual(error as? PreferencesImportError, .tooManyDevices)
        }

        preferences = .defaults
        preferences.customPresets = [
            LightPreset(
                id: "long-flow",
                title: "Long Flow",
                kind: .flow,
                flow: ColorFlow(steps: Array(repeating: .sleep(100), count: 61))
            )
        ]
        XCTAssertThrowsError(try state.applyImportedPreferences(JSONEncoder().encode(preferences))) { error in
            XCTAssertEqual(error as? PreferencesImportError, .flowHasTooManySteps)
        }
    }

    func testImportRemovesPresetIDCollisionsAndPreservesZeroFavorites() throws {
        let store = makeIsolatedStore()
        let state = AppState(store: store)
        var preferences = AppPreferences.defaults
        preferences.customPresets = [
            LightPreset(id: LightPreset.reading.id, title: "Collision", kind: .color),
            LightPreset(id: "custom", title: "First", kind: .color),
            LightPreset(id: "custom", title: "Duplicate", kind: .color)
        ]
        preferences.favoritePresetIDs = []

        try state.applyImportedPreferences(JSONEncoder().encode(preferences))

        XCTAssertEqual(state.customPresets.map(\.id), ["custom"])
        XCTAssertTrue(state.favoritePresetIDs.isEmpty)
        XCTAssertTrue(state.favoritePresets.isEmpty)
        XCTAssertTrue(store.load().favoritePresetIDs.isEmpty)
    }

    func testLaunchAtLoginRollsBackAndSurfacesRequiredApproval() {
        let manager = FakeLaunchAtLoginManager(state: .disabled)
        let state = AppState(store: makeIsolatedStore(), launchAtLoginManager: manager)

        manager.error = FakeLaunchAtLoginManager.TestError.failed
        state.setLaunchAtLogin(true)
        XCTAssertFalse(state.launchAtLogin)

        manager.error = nil
        manager.nextState = .requiresApproval
        state.setLaunchAtLogin(true)
        XCTAssertFalse(state.launchAtLogin)
        XCTAssertTrue(state.launchAtLoginRequiresApproval)

        manager.nextState = .enabled
        state.setLaunchAtLogin(true)
        XCTAssertTrue(state.launchAtLogin)
        XCTAssertFalse(state.launchAtLoginRequiresApproval)
    }

    private func makeIsolatedStore() -> DeviceStore {
        let suiteName = "YeelightBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DeviceStore(defaults: defaults)
    }

    private func makeDevice(state: DeviceState) -> YeelightDevice {
        YeelightDevice(
            id: "test-device",
            name: "Desk Lamp",
            model: "color",
            host: "192.168.1.42",
            port: 55443,
            capabilities: ["set_scene", "start_cf"],
            state: state,
            lastSeen: Date(timeIntervalSince1970: 0)
        )
    }
}

@MainActor
private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    enum TestError: Error {
        case failed
    }

    private(set) var state: LaunchAtLoginState
    var nextState: LaunchAtLoginState?
    var error: Error?

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func setEnabled(_ enabled: Bool) throws {
        if let error {
            throw error
        }
        state = nextState ?? (enabled ? .enabled : .disabled)
    }
}
