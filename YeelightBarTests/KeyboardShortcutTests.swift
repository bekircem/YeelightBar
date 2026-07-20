import Carbon
import XCTest
@testable import YeelightBar

@MainActor
final class KeyboardShortcutTests: XCTestCase {
    func testDefaultShortcutSetMatchesExpectedCombinations() {
        let shortcuts = Dictionary(uniqueKeysWithValues: ConfiguredShortcut.defaultSet.map { ($0.action, $0) })

        XCTAssertEqual(shortcuts[.togglePower]?.combination?.displayString, "⌃⌥⌘L")
        XCTAssertEqual(shortcuts[.cycleWhiteColorMode]?.combination?.displayString, "⌃⌥⌘M")
        XCTAssertEqual(shortcuts[.nextFavoritePreset]?.combination?.displayString, "⌃⌥⌘N")
        XCTAssertEqual(shortcuts[.previousFavoritePreset]?.combination?.displayString, "⌃⌥⌘P")
        XCTAssertEqual(shortcuts[.brightnessUp]?.combination?.displayString, "⌃⌥⌘↑")
        XCTAssertEqual(shortcuts[.brightnessDown]?.combination?.displayString, "⌃⌥⌘↓")
        XCTAssertNil(shortcuts[.stopFlow]?.combination)
        XCTAssertFalse(shortcuts[.stopFlow]?.isEnabled ?? true)
    }

    func testShortcutValidationRequiresTwoModifiers() {
        let valid = HotKeyCombination(keyCode: 37, modifiers: [.control, .option], keyLabel: "L")
        let invalid = HotKeyCombination(keyCode: 37, modifiers: [.control], keyLabel: "L")

        XCTAssertNil(valid.validationError)
        XCTAssertEqual(invalid.validationError, "Use at least two modifier keys.")
    }

    func testGlobalHotKeyManagerRegistersConflictsAndDispatchesActions() {
        let registrar = FakeHotKeyRegistrar()
        let manager = GlobalHotKeyManager(registrar: registrar)
        var dispatchedTarget: KeyboardShortcutTarget?
        manager.onTarget = { dispatchedTarget = $0 }

        let result = manager.apply(
            shortcuts: ConfiguredShortcut.defaultSet,
            presetShortcuts: [],
            availablePresetIDs: [],
            enabled: true
        )

        XCTAssertEqual(result.actionStatuses[.togglePower], .registered)
        XCTAssertEqual(result.actionStatuses[.stopFlow], .disabled)
        XCTAssertEqual(registrar.registeredIDs.count, 6)

        registrar.trigger(id: KeyboardShortcutAction.nextFavoritePreset.hotKeyID)

        XCTAssertEqual(dispatchedTarget, .action(.nextFavoritePreset))

        registrar.resultsByID[KeyboardShortcutAction.togglePower.hotKeyID] = OSStatus(eventHotKeyExistsErr)
        let conflictResult = manager.apply(
            shortcuts: ConfiguredShortcut.defaultSet,
            presetShortcuts: [],
            availablePresetIDs: [],
            enabled: true
        )

        XCTAssertEqual(conflictResult.actionStatuses[.togglePower], .conflict)
        XCTAssertGreaterThanOrEqual(registrar.unregisterAllCount, 1)
    }

    func testGlobalHotKeyManagerRegistersDynamicPresetShortcut() {
        let registrar = FakeHotKeyRegistrar()
        let manager = GlobalHotKeyManager(registrar: registrar)
        let shortcut = PresetShortcut(
            presetID: LightPreset.warmAmber.id,
            combination: HotKeyCombination(keyCode: 8, modifiers: [.control, .option, .command], keyLabel: "C"),
            isEnabled: true
        )
        var dispatchedTarget: KeyboardShortcutTarget?
        manager.onTarget = { dispatchedTarget = $0 }

        let result = manager.apply(
            shortcuts: ConfiguredShortcut.defaultSet,
            presetShortcuts: [shortcut],
            availablePresetIDs: Set(LightPreset.builtIns.map(\.id)),
            enabled: true
        )

        XCTAssertEqual(result.presetShortcutStatuses[shortcut.id], .registered)

        let dynamicID = registrar.registeredIDs.max()!
        registrar.trigger(id: dynamicID)

        XCTAssertEqual(dispatchedTarget, .presetShortcut(shortcut.id))
    }

    func testGlobalHotKeyManagerMarksMissingPresetShortcutInvalidForRegistration() {
        let registrar = FakeHotKeyRegistrar()
        let manager = GlobalHotKeyManager(registrar: registrar)
        let shortcut = PresetShortcut(
            presetID: "deleted-custom-mode",
            combination: HotKeyCombination(keyCode: 8, modifiers: [.control, .option, .command], keyLabel: "C"),
            isEnabled: true
        )

        let result = manager.apply(
            shortcuts: ConfiguredShortcut.defaultSet,
            presetShortcuts: [shortcut],
            availablePresetIDs: Set(LightPreset.builtIns.map(\.id)),
            enabled: true
        )

        XCTAssertEqual(result.presetShortcutStatuses[shortcut.id], .missingPreset)
    }

    func testAppStateRejectsDuplicateShortcutAndPersistsValidShortcut() {
        let store = makeIsolatedStore()
        let state = AppState(store: store, hotKeyManager: DisabledGlobalHotKeyManager())
        let duplicate = KeyboardShortcutAction.togglePower.defaultCombination!
        let custom = HotKeyCombination(keyCode: 1, modifiers: [.control, .option, .command], keyLabel: "S")

        XCTAssertFalse(state.assignShortcut(action: .stopFlow, combination: duplicate))
        XCTAssertNil(state.shortcut(for: .stopFlow).combination)

        XCTAssertTrue(state.assignShortcut(action: .stopFlow, combination: custom))

        let savedShortcut = store.load().keyboardShortcuts.first { $0.action == .stopFlow }
        XCTAssertEqual(savedShortcut?.combination, custom)
        XCTAssertEqual(savedShortcut?.isEnabled, true)
    }

    func testAppStateManagesPresetShortcutsAndRejectsDuplicates() {
        let store = makeIsolatedStore()
        let state = AppState(store: store, hotKeyManager: DisabledGlobalHotKeyManager())
        let firstID = state.addPresetShortcut()
        let secondID = state.addPresetShortcut()
        let directCombination = HotKeyCombination(keyCode: 8, modifiers: [.control, .option, .command], keyLabel: "C")

        state.setPresetShortcutPreset(id: firstID, presetID: LightPreset.warmAmber.id)

        XCTAssertTrue(state.assignPresetShortcut(id: firstID, combination: directCombination))
        XCTAssertFalse(state.assignPresetShortcut(id: secondID, combination: directCombination))

        var savedShortcuts = store.load().presetShortcuts
        XCTAssertEqual(savedShortcuts.count, 2)
        XCTAssertEqual(savedShortcuts.first { $0.id == firstID }?.presetID, LightPreset.warmAmber.id)
        XCTAssertEqual(savedShortcuts.first { $0.id == firstID }?.combination, directCombination)

        state.clearPresetShortcut(id: firstID)
        savedShortcuts = store.load().presetShortcuts
        XCTAssertNil(savedShortcuts.first { $0.id == firstID }?.combination)

        state.deletePresetShortcut(id: secondID)
        savedShortcuts = store.load().presetShortcuts
        XCTAssertNil(savedShortcuts.first { $0.id == secondID })
    }

    private func makeIsolatedStore() -> DeviceStore {
        let suiteName = "YeelightBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DeviceStore(defaults: defaults)
    }
}

@MainActor
private final class FakeHotKeyRegistrar: HotKeyRegistering {
    var registeredIDs: [UInt32] = []
    var unregisterAllCount = 0
    var resultsByID: [UInt32: OSStatus] = [:]

    private var handler: (@MainActor (UInt32) -> Void)?

    func install(handler: @escaping @MainActor (UInt32) -> Void) {
        self.handler = handler
    }

    func register(id: UInt32, combination: HotKeyCombination) -> OSStatus {
        registeredIDs.append(id)
        return resultsByID[id] ?? noErr
    }

    func unregister(id: UInt32) {
        registeredIDs.removeAll { $0 == id }
    }

    func unregisterAll() {
        unregisterAllCount += 1
        registeredIDs = []
    }

    func trigger(id: UInt32) {
        handler?(id)
    }
}
