import Carbon
import Foundation

@MainActor
protocol GlobalHotKeyManaging: AnyObject {
    var onTarget: ((KeyboardShortcutTarget) -> Void)? { get set }

    func apply(
        shortcuts: [ConfiguredShortcut],
        presetShortcuts: [PresetShortcut],
        availablePresetIDs: Set<String>,
        enabled: Bool
    ) -> HotKeyRegistrationResult
    func unregisterAll()
}

@MainActor
protocol HotKeyRegistering: AnyObject {
    func install(handler: @escaping @MainActor (UInt32) -> Void)
    func register(id: UInt32, combination: HotKeyCombination) -> OSStatus
    func unregister(id: UInt32)
    func unregisterAll()
}

@MainActor
final class GlobalHotKeyManager: GlobalHotKeyManaging {
    var onTarget: ((KeyboardShortcutTarget) -> Void)?

    private let registrar: HotKeyRegistering
    private var targetByID: [UInt32: KeyboardShortcutTarget] = [:]

    init(registrar: HotKeyRegistering = CarbonHotKeyRegistrar()) {
        self.registrar = registrar

        registrar.install { [weak self] id in
            self?.handleHotKey(id: id)
        }
    }

    func apply(
        shortcuts: [ConfiguredShortcut],
        presetShortcuts: [PresetShortcut],
        availablePresetIDs: Set<String>,
        enabled: Bool
    ) -> HotKeyRegistrationResult {
        registrar.unregisterAll()
        targetByID = [:]

        var actionStatuses = Dictionary(
            uniqueKeysWithValues: KeyboardShortcutAction.allCases.map { action in
                (action, enabled ? HotKeyRegistrationStatus.unassigned : .disabled)
            }
        )
        var presetStatuses = Dictionary(
            uniqueKeysWithValues: presetShortcuts.map { shortcut in
                (shortcut.id, enabled ? HotKeyRegistrationStatus.unassigned : .disabled)
            }
        )

        guard enabled else {
            return HotKeyRegistrationResult(
                actionStatuses: actionStatuses,
                presetShortcutStatuses: presetStatuses
            )
        }

        let shortcutsByAction = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.action, $0) })
        var seenCombinations: [HotKeyCombination: KeyboardShortcutTarget] = [:]

        for action in KeyboardShortcutAction.allCases {
            guard let shortcut = shortcutsByAction[action], shortcut.isEnabled else {
                actionStatuses[action] = .disabled
                continue
            }

            guard let combination = shortcut.combination else {
                actionStatuses[action] = .unassigned
                continue
            }

            if let validationError = combination.validationError {
                actionStatuses[action] = .invalid(validationError)
                continue
            }

            let target = KeyboardShortcutTarget.action(action)
            if let duplicateTarget = seenCombinations[combination] {
                actionStatuses[action] = .invalid("Duplicate of \(duplicateTarget.title).")
                continue
            }

            seenCombinations[combination] = target

            let status = registrar.register(id: action.hotKeyID, combination: combination)
            actionStatuses[action] = registrationStatus(for: status)
            if status == noErr {
                targetByID[action.hotKeyID] = target
            }
        }

        for (offset, shortcut) in presetShortcuts.enumerated() {
            guard let combination = shortcut.combination else {
                presetStatuses[shortcut.id] = .unassigned
                continue
            }

            guard shortcut.isEnabled else {
                presetStatuses[shortcut.id] = .disabled
                continue
            }

            guard let presetID = shortcut.presetID, availablePresetIDs.contains(presetID) else {
                presetStatuses[shortcut.id] = .missingPreset
                continue
            }

            if let validationError = combination.validationError {
                presetStatuses[shortcut.id] = .invalid(validationError)
                continue
            }

            let target = KeyboardShortcutTarget.presetShortcut(shortcut.id)
            if let duplicateTarget = seenCombinations[combination] {
                presetStatuses[shortcut.id] = .invalid("Duplicate of \(duplicateTarget.title).")
                continue
            }

            guard let hotKeyID = presetShortcutHotKeyID(offset: offset) else {
                presetStatuses[shortcut.id] = .failed(-1)
                continue
            }

            seenCombinations[combination] = target

            let status = registrar.register(id: hotKeyID, combination: combination)
            presetStatuses[shortcut.id] = registrationStatus(for: status)
            if status == noErr {
                targetByID[hotKeyID] = target
            }
        }

        return HotKeyRegistrationResult(
            actionStatuses: actionStatuses,
            presetShortcutStatuses: presetStatuses
        )
    }

    func unregisterAll() {
        registrar.unregisterAll()
        targetByID = [:]
    }

    private func handleHotKey(id: UInt32) {
        guard let target = targetByID[id] else {
            return
        }

        onTarget?(target)
    }

    private func registrationStatus(for status: OSStatus) -> HotKeyRegistrationStatus {
        switch status {
        case noErr:
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            return .conflict
        case OSStatus(eventHotKeyInvalidErr):
            return .invalid("macOS rejected this shortcut.")
        default:
            return .failed(status)
        }
    }

    private func presetShortcutHotKeyID(offset: Int) -> UInt32? {
        let baseID: UInt32 = 10_000
        guard offset <= Int(UInt32.max - baseID) else {
            return nil
        }
        return baseID + UInt32(offset)
    }
}

@MainActor
final class DisabledGlobalHotKeyManager: GlobalHotKeyManaging {
    var onTarget: ((KeyboardShortcutTarget) -> Void)?

    func apply(
        shortcuts: [ConfiguredShortcut],
        presetShortcuts: [PresetShortcut],
        availablePresetIDs: Set<String>,
        enabled: Bool
    ) -> HotKeyRegistrationResult {
        let actionStatuses = Dictionary(
            uniqueKeysWithValues: KeyboardShortcutAction.allCases.map { action in
                let shortcut = shortcuts.first { $0.action == action }
                let status: HotKeyRegistrationStatus
                if !enabled || shortcut?.isEnabled == false {
                    status = .disabled
                } else if shortcut?.combination == nil {
                    status = .unassigned
                } else {
                    status = .registered
                }
                return (action, status)
            }
        )
        let presetStatuses = Dictionary(
            uniqueKeysWithValues: presetShortcuts.map { shortcut in
                let status: HotKeyRegistrationStatus
                if !enabled {
                    status = .disabled
                } else if shortcut.combination == nil {
                    status = .unassigned
                } else if !shortcut.isEnabled {
                    status = .disabled
                } else if shortcut.presetID.map({ availablePresetIDs.contains($0) }) != true {
                    status = .missingPreset
                } else {
                    status = .registered
                }
                return (shortcut.id, status)
            }
        )
        return HotKeyRegistrationResult(
            actionStatuses: actionStatuses,
            presetShortcutStatuses: presetStatuses
        )
    }

    func unregisterAll() { }
}

@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistering {
    fileprivate var callback: (@MainActor (UInt32) -> Void)?

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var handlerRef: EventHandlerRef?

    func install(handler: @escaping @MainActor (UInt32) -> Void) {
        callback = handler

        guard handlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyHandler,
            1,
            &eventType,
            userData,
            &handlerRef
        )
    }

    func register(id: UInt32, combination: HotKeyCombination) -> OSStatus {
        unregister(id: id)

        let hotKeyID = EventHotKeyID(signature: yeelightHotKeySignature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &ref
        )

        if status == noErr, let ref {
            hotKeyRefs[id] = ref
        }

        return status
    }

    func unregister(id: UInt32) {
        guard let ref = hotKeyRefs.removeValue(forKey: id) else {
            return
        }

        UnregisterEventHotKey(ref)
    }

    func unregisterAll() {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs = [:]
    }

}

private let yeelightHotKeySignature: OSType = 0x5942_484B

private let carbonHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    if status == noErr {
        let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in
            registrar.callback?(hotKeyID.id)
        }
    }

    return noErr
}

private extension HotKeyCombination {
    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) {
            value |= UInt32(cmdKey)
        }
        if modifiers.contains(.option) {
            value |= UInt32(optionKey)
        }
        if modifiers.contains(.shift) {
            value |= UInt32(shiftKey)
        }
        if modifiers.contains(.control) {
            value |= UInt32(controlKey)
        }
        return value
    }
}
