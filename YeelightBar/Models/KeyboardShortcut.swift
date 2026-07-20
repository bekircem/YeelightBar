import AppKit
import Foundation

enum KeyboardShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case togglePower
    case cycleWhiteColorMode
    case nextFavoritePreset
    case previousFavoritePreset
    case brightnessUp
    case brightnessDown
    case stopFlow

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .togglePower:
            return "Toggle Power"
        case .cycleWhiteColorMode:
            return "Cycle White / Color"
        case .nextFavoritePreset:
            return "Next Favorite"
        case .previousFavoritePreset:
            return "Previous Favorite"
        case .brightnessUp:
            return "Brightness Up"
        case .brightnessDown:
            return "Brightness Down"
        case .stopFlow:
            return "Stop Flow"
        }
    }

    var subtitle: String {
        switch self {
        case .togglePower:
            return "Turn the selected bulb on or off."
        case .cycleWhiteColorMode:
            return "Switch between white temperature and color mode."
        case .nextFavoritePreset:
            return "Apply the next starred mode or flow."
        case .previousFavoritePreset:
            return "Apply the previous starred mode or flow."
        case .brightnessUp:
            return "Increase brightness by the configured step."
        case .brightnessDown:
            return "Decrease brightness by the configured step."
        case .stopFlow:
            return "Stop a running color flow."
        }
    }

    var symbolName: String {
        switch self {
        case .togglePower:
            return "power"
        case .cycleWhiteColorMode:
            return "circle.lefthalf.filled"
        case .nextFavoritePreset:
            return "forward.fill"
        case .previousFavoritePreset:
            return "backward.fill"
        case .brightnessUp:
            return "sun.max.fill"
        case .brightnessDown:
            return "sun.min.fill"
        case .stopFlow:
            return "stop.fill"
        }
    }

    var hotKeyID: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self) ?? 0) + 1
    }

    var defaultCombination: HotKeyCombination? {
        switch self {
        case .togglePower:
            return HotKeyCombination(keyCode: 37, modifiers: [.control, .option, .command], keyLabel: "L")
        case .cycleWhiteColorMode:
            return HotKeyCombination(keyCode: 46, modifiers: [.control, .option, .command], keyLabel: "M")
        case .nextFavoritePreset:
            return HotKeyCombination(keyCode: 45, modifiers: [.control, .option, .command], keyLabel: "N")
        case .previousFavoritePreset:
            return HotKeyCombination(keyCode: 35, modifiers: [.control, .option, .command], keyLabel: "P")
        case .brightnessUp:
            return HotKeyCombination(keyCode: 126, modifiers: [.control, .option, .command], keyLabel: "↑")
        case .brightnessDown:
            return HotKeyCombination(keyCode: 125, modifiers: [.control, .option, .command], keyLabel: "↓")
        case .stopFlow:
            return nil
        }
    }
}

struct HotKeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: UInt32

    static let control = HotKeyModifiers(rawValue: 1 << 0)
    static let option = HotKeyModifiers(rawValue: 1 << 1)
    static let shift = HotKeyModifiers(rawValue: 1 << 2)
    static let command = HotKeyModifiers(rawValue: 1 << 3)

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt32.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayString: String {
        var parts: [String] = []
        if contains(.control) {
            parts.append("⌃")
        }
        if contains(.option) {
            parts.append("⌥")
        }
        if contains(.shift) {
            parts.append("⇧")
        }
        if contains(.command) {
            parts.append("⌘")
        }
        return parts.joined()
    }

    var count: Int {
        var value = rawValue
        var count = 0
        while value > 0 {
            count += Int(value & 1)
            value >>= 1
        }
        return count
    }

    static func from(eventFlags: NSEvent.ModifierFlags) -> HotKeyModifiers {
        let flags = eventFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: HotKeyModifiers = []
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        return modifiers
    }
}

struct HotKeyCombination: Codable, Equatable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: HotKeyModifiers
    var keyLabel: String

    var displayString: String {
        "\(modifiers.displayString)\(keyLabel)"
    }

    init(keyCode: UInt32, modifiers: HotKeyModifiers, keyLabel: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel ?? Self.defaultKeyLabel(for: keyCode)
    }

    init?(event: NSEvent) {
        let label = Self.keyLabel(for: event)
        guard !label.isEmpty else {
            return nil
        }

        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: .from(eventFlags: event.modifierFlags),
            keyLabel: label
        )
    }

    var validationError: String? {
        if keyLabel.isEmpty {
            return "Shortcut must include a key."
        }

        if modifiers.count < 2 {
            return "Use at least two modifier keys."
        }

        return nil
    }

    private static func keyLabel(for event: NSEvent) -> String {
        let mapped = defaultKeyLabel(for: UInt32(event.keyCode))
        if !mapped.hasPrefix("Key ") {
            return mapped
        }

        let characters = event.charactersIgnoringModifiers ?? event.characters ?? ""
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first else {
            return mapped
        }

        return String(scalar).uppercased()
    }

    static func defaultKeyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 0:
            return "A"
        case 1:
            return "S"
        case 2:
            return "D"
        case 3:
            return "F"
        case 4:
            return "H"
        case 5:
            return "G"
        case 6:
            return "Z"
        case 7:
            return "X"
        case 8:
            return "C"
        case 9:
            return "V"
        case 11:
            return "B"
        case 12:
            return "Q"
        case 13:
            return "W"
        case 14:
            return "E"
        case 15:
            return "R"
        case 16:
            return "Y"
        case 17:
            return "T"
        case 31:
            return "O"
        case 32:
            return "U"
        case 34:
            return "I"
        case 35:
            return "P"
        case 37:
            return "L"
        case 38:
            return "J"
        case 40:
            return "K"
        case 45:
            return "N"
        case 46:
            return "M"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        default:
            return "Key \(keyCode)"
        }
    }
}

struct ConfiguredShortcut: Codable, Equatable, Identifiable, Sendable {
    var action: KeyboardShortcutAction
    var combination: HotKeyCombination?
    var isEnabled: Bool

    var id: KeyboardShortcutAction {
        action
    }

    static let defaultSet: [ConfiguredShortcut] = KeyboardShortcutAction.allCases.map { action in
        let combination = action.defaultCombination
        return ConfiguredShortcut(
            action: action,
            combination: combination,
            isEnabled: combination != nil
        )
    }
}

struct PresetShortcut: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var presetID: String?
    var combination: HotKeyCombination?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        presetID: String? = nil,
        combination: HotKeyCombination? = nil,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.presetID = presetID
        self.combination = combination
        self.isEnabled = isEnabled
    }
}

enum KeyboardShortcutTarget: Equatable, Hashable, Sendable {
    case action(KeyboardShortcutAction)
    case presetShortcut(UUID)

    var title: String {
        switch self {
        case .action(let action):
            return action.title
        case .presetShortcut:
            return "Direct Mode Shortcut"
        }
    }
}

struct HotKeyRegistrationResult: Equatable {
    var actionStatuses: [KeyboardShortcutAction: HotKeyRegistrationStatus]
    var presetShortcutStatuses: [UUID: HotKeyRegistrationStatus]

    static let empty = HotKeyRegistrationResult(actionStatuses: [:], presetShortcutStatuses: [:])
}

enum HotKeyRegistrationStatus: Equatable {
    case disabled
    case unassigned
    case registered
    case missingPreset
    case conflict
    case invalid(String)
    case failed(Int32)

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .unassigned:
            return "Not Set"
        case .registered:
            return "Active"
        case .missingPreset:
            return "Mode Missing"
        case .conflict:
            return "Conflict"
        case .invalid:
            return "Invalid"
        case .failed:
            return "Failed"
        }
    }

    var detail: String? {
        switch self {
        case .missingPreset:
            return "Select an available mode for this shortcut."
        case .invalid(let message):
            return message
        case .failed(let status):
            return "OSStatus \(status)"
        case .conflict:
            return "Another app is already using this shortcut."
        default:
            return nil
        }
    }
}
