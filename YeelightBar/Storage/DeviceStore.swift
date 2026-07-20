import Foundation

enum MenuBarIconStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case connectionStatus
    case outline
    case filled

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .connectionStatus:
            return "Connection Status"
        case .outline:
            return "Outline Bulb"
        case .filled:
            return "Filled Bulb"
        }
    }
}

enum ControlDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case detailed
    case compact

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .detailed:
            return "Detailed"
        case .compact:
            return "Compact"
        }
    }
}

struct AppPreferences: Codable, Equatable, Sendable {
    var savedDevices: [YeelightDevice]
    var selectedDeviceID: String?
    var transitionDuration: Int
    var discoveryRetryInterval: Double
    var launchAtLogin: Bool
    var menuBarIconStyle: MenuBarIconStyle
    var defaultManualPort: UInt16
    var commandTimeout: Double
    var reconnectInterval: Double
    var brightnessDebounceMilliseconds: Int
    var colorDebounceMilliseconds: Int
    var popoverWidth: Double
    var controlDisplayMode: ControlDisplayMode
    var showColorControl: Bool
    var debugLoggingEnabled: Bool
    var customPresets: [LightPreset]
    var favoritePresetIDs: [String]
    var selectedPresetID: String
    var shortcutsEnabled: Bool
    var keyboardShortcuts: [ConfiguredShortcut]
    var presetShortcuts: [PresetShortcut]
    var shortcutBrightnessStep: Int

    static let defaults = AppPreferences(
        savedDevices: [],
        selectedDeviceID: nil,
        transitionDuration: 500,
        discoveryRetryInterval: 15,
        launchAtLogin: false,
        menuBarIconStyle: .connectionStatus,
        defaultManualPort: 55443,
        commandTimeout: 5,
        reconnectInterval: 2,
        brightnessDebounceMilliseconds: 180,
        colorDebounceMilliseconds: 180,
        popoverWidth: 340,
        controlDisplayMode: .detailed,
        showColorControl: true,
        debugLoggingEnabled: false,
        customPresets: [],
        favoritePresetIDs: LightPreset.defaultFavoriteIDs,
        selectedPresetID: LightPreset.reading.id,
        shortcutsEnabled: true,
        keyboardShortcuts: ConfiguredShortcut.defaultSet,
        presetShortcuts: [],
        shortcutBrightnessStep: 10
    )

    init(
        savedDevices: [YeelightDevice],
        selectedDeviceID: String?,
        transitionDuration: Int,
        discoveryRetryInterval: Double,
        launchAtLogin: Bool,
        menuBarIconStyle: MenuBarIconStyle = .connectionStatus,
        defaultManualPort: UInt16 = 55443,
        commandTimeout: Double = 5,
        reconnectInterval: Double = 2,
        brightnessDebounceMilliseconds: Int = 180,
        colorDebounceMilliseconds: Int = 180,
        popoverWidth: Double = 340,
        controlDisplayMode: ControlDisplayMode = .detailed,
        showColorControl: Bool = true,
        debugLoggingEnabled: Bool = false,
        customPresets: [LightPreset] = [],
        favoritePresetIDs: [String] = LightPreset.defaultFavoriteIDs,
        selectedPresetID: String = LightPreset.reading.id,
        shortcutsEnabled: Bool = true,
        keyboardShortcuts: [ConfiguredShortcut] = ConfiguredShortcut.defaultSet,
        presetShortcuts: [PresetShortcut] = [],
        shortcutBrightnessStep: Int = 10
    ) {
        self.savedDevices = savedDevices
        self.selectedDeviceID = selectedDeviceID
        self.transitionDuration = transitionDuration
        self.discoveryRetryInterval = discoveryRetryInterval
        self.launchAtLogin = launchAtLogin
        self.menuBarIconStyle = menuBarIconStyle
        self.defaultManualPort = defaultManualPort
        self.commandTimeout = commandTimeout
        self.reconnectInterval = reconnectInterval
        self.brightnessDebounceMilliseconds = brightnessDebounceMilliseconds
        self.colorDebounceMilliseconds = colorDebounceMilliseconds
        self.popoverWidth = popoverWidth
        self.controlDisplayMode = controlDisplayMode
        self.showColorControl = showColorControl
        self.debugLoggingEnabled = debugLoggingEnabled
        self.customPresets = customPresets
        self.favoritePresetIDs = favoritePresetIDs
        self.selectedPresetID = selectedPresetID
        self.shortcutsEnabled = shortcutsEnabled
        self.keyboardShortcuts = keyboardShortcuts
        self.presetShortcuts = presetShortcuts
        self.shortcutBrightnessStep = shortcutBrightnessStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults

        savedDevices = try container.decodeIfPresent([YeelightDevice].self, forKey: .savedDevices) ?? defaults.savedDevices
        selectedDeviceID = try container.decodeIfPresent(String.self, forKey: .selectedDeviceID) ?? defaults.selectedDeviceID
        transitionDuration = try container.decodeIfPresent(Int.self, forKey: .transitionDuration) ?? defaults.transitionDuration
        discoveryRetryInterval = try container.decodeIfPresent(Double.self, forKey: .discoveryRetryInterval) ?? defaults.discoveryRetryInterval
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? defaults.menuBarIconStyle
        defaultManualPort = try container.decodeIfPresent(UInt16.self, forKey: .defaultManualPort) ?? defaults.defaultManualPort
        commandTimeout = try container.decodeIfPresent(Double.self, forKey: .commandTimeout) ?? defaults.commandTimeout
        reconnectInterval = try container.decodeIfPresent(Double.self, forKey: .reconnectInterval) ?? defaults.reconnectInterval
        brightnessDebounceMilliseconds = try container.decodeIfPresent(Int.self, forKey: .brightnessDebounceMilliseconds) ?? defaults.brightnessDebounceMilliseconds
        colorDebounceMilliseconds = try container.decodeIfPresent(Int.self, forKey: .colorDebounceMilliseconds) ?? defaults.colorDebounceMilliseconds
        popoverWidth = try container.decodeIfPresent(Double.self, forKey: .popoverWidth) ?? defaults.popoverWidth
        controlDisplayMode = try container.decodeIfPresent(ControlDisplayMode.self, forKey: .controlDisplayMode) ?? defaults.controlDisplayMode
        showColorControl = try container.decodeIfPresent(Bool.self, forKey: .showColorControl) ?? defaults.showColorControl
        debugLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? defaults.debugLoggingEnabled
        customPresets = try container.decodeIfPresent([LightPreset].self, forKey: .customPresets) ?? defaults.customPresets
        favoritePresetIDs = try container.decodeIfPresent([String].self, forKey: .favoritePresetIDs) ?? defaults.favoritePresetIDs
        selectedPresetID = try container.decodeIfPresent(String.self, forKey: .selectedPresetID) ?? defaults.selectedPresetID
        shortcutsEnabled = try container.decodeIfPresent(Bool.self, forKey: .shortcutsEnabled) ?? defaults.shortcutsEnabled
        keyboardShortcuts = try container.decodeIfPresent([ConfiguredShortcut].self, forKey: .keyboardShortcuts) ?? defaults.keyboardShortcuts
        presetShortcuts = try container.decodeIfPresent([PresetShortcut].self, forKey: .presetShortcuts) ?? defaults.presetShortcuts
        shortcutBrightnessStep = try container.decodeIfPresent(Int.self, forKey: .shortcutBrightnessStep) ?? defaults.shortcutBrightnessStep
    }
}

final class DeviceStore {
    private let key = "io.github.bekircem.yeelightbar.preferences"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(AppPreferences.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ preferences: AppPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
final class PreferenceSaveScheduler {
    private let delayNanoseconds: UInt64
    private let save: (AppPreferences) -> Void
    private var pendingPreferences: AppPreferences?
    private var saveTask: Task<Void, Never>?
    private(set) var saveCount = 0

    init(delay: TimeInterval = 0.5, save: @escaping (AppPreferences) -> Void) {
        self.delayNanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        self.save = save
    }

    func schedule(_ preferences: AppPreferences) {
        pendingPreferences = preferences
        saveTask?.cancel()

        saveTask = Task { [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            self.flushPending()
        }
    }

    func flush(_ preferences: AppPreferences) {
        saveTask?.cancel()
        saveTask = nil
        pendingPreferences = nil
        save(preferences)
        saveCount += 1
    }

    func flushPending() {
        guard let pendingPreferences else {
            return
        }

        saveTask?.cancel()
        saveTask = nil
        self.pendingPreferences = nil
        save(pendingPreferences)
        saveCount += 1
    }
}
