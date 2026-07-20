import AppKit
import Foundation
import Network
import OSLog
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum AppConnectionStatus: Equatable {
    case idle
    case searching
    case connected
    case offline
    case notFound
    case error(String)

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .searching:
            return "Searching"
        case .connected:
            return "Connected"
        case .offline:
            return "Offline"
        case .notFound:
            return "LAN Control not found"
        case .error(let message):
            return message
        }
    }

    var symbolName: String {
        switch self {
        case .connected:
            return "lightbulb.fill"
        case .searching:
            return "dot.radiowaves.left.and.right"
        case .offline, .notFound, .error:
            return "lightbulb.slash"
        case .idle:
            return "lightbulb"
        }
    }
}

enum LightControlMode: String, CaseIterable, Identifiable, Equatable {
    case white
    case color
    case flow

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .white:
            return "White"
        case .color:
            return "Color"
        case .flow:
            return "Flow"
        }
    }

    var symbolName: String {
        switch self {
        case .white:
            return "sun.max"
        case .color:
            return "paintpalette"
        case .flow:
            return "waveform"
        }
    }

    static func inferred(from state: DeviceState) -> LightControlMode {
        if state.flowing {
            return .flow
        }

        switch state.colorMode {
        case .rgb, .hsv:
            return .color
        case .colorTemperature, .unknown:
            return .white
        }
    }
}

private enum ColorCommandSignature: Equatable {
    case rgb(Int)
    case hsv(hue: Int, saturation: Int)
}

private enum DiagnosticLevel {
    case debug
    case info
    case error
}

private struct DiagnosticRing {
    private let capacity: Int
    private var events: [String] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    mutating func insert(_ event: String) -> [String] {
        events.insert(event, at: 0)

        if events.count > capacity {
            events.removeLast(events.count - capacity)
        }

        return events
    }

    mutating func removeAll() -> [String] {
        events.removeAll()
        return events
    }
}

private struct PresetSnapshot {
    var builtInPresets: [LightPreset]
    var availablePresets: [LightPreset]
    var whitePresets: [LightPreset]
    var colorPresets: [LightPreset]
    var flowPresets: [LightPreset]
    var favoritePresets: [LightPreset]

    static func make(customPresets: [LightPreset], favoritePresetIDs: [String]) -> PresetSnapshot {
        let builtInPresets = LightPreset.builtIns
        let availablePresets = builtInPresets + customPresets
        let favorites = favoritePresetIDs.compactMap { id in
            availablePresets.first { $0.id == id }
        }

        return PresetSnapshot(
            builtInPresets: builtInPresets,
            availablePresets: availablePresets,
            whitePresets: availablePresets.filter { $0.kind == .colorTemperature },
            colorPresets: availablePresets.filter { $0.kind == .color || $0.kind == .hsv },
            flowPresets: availablePresets.filter { $0.kind == .flow },
            favoritePresets: favorites
        )
    }

    static let empty = PresetSnapshot.make(
        customPresets: [],
        favoritePresetIDs: LightPreset.defaultFavoriteIDs
    )
}

private struct DeviceViewSnapshot {
    var endpoint: String
    var capabilitiesText: String

    static let empty = DeviceViewSnapshot(endpoint: "", capabilitiesText: "None")

    static func make(device: YeelightDevice?) -> DeviceViewSnapshot {
        guard let device else {
            return .empty
        }

        let capabilities = device.capabilities.sorted()
        return DeviceViewSnapshot(
            endpoint: "\(device.host):\(device.port)",
            capabilitiesText: capabilities.isEmpty ? "None" : capabilities.joined(separator: ", ")
        )
    }
}

private struct ConnectionSession {
    let id: UUID
    let deviceID: String
    let connection: YeelightConnection
}

enum LaunchAtLoginState: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

@MainActor
protocol LaunchAtLoginManaging {
    var state: LaunchAtLoginState { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var state: LaunchAtLoginState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .disabled
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum PreferencesImportError: LocalizedError, Equatable {
    case fileTooLarge
    case tooManyDevices
    case tooManyPresets
    case tooManyShortcuts
    case flowHasTooManySteps

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return "The settings file is larger than 5 MiB."
        case .tooManyDevices:
            return "The settings file contains more than 100 devices."
        case .tooManyPresets:
            return "The settings file contains more than 500 custom modes."
        case .tooManyShortcuts:
            return "The settings file contains more than 100 direct shortcuts."
        case .flowHasTooManySteps:
            return "A flow contains more than 60 steps."
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    nonisolated private static let statePropertyKeys = [
        "power",
        "bright",
        "ct",
        "rgb",
        "hue",
        "sat",
        "color_mode",
        "flowing",
        "flow_params",
        "delayoff"
    ]

    nonisolated static func effectiveDiscoveryRetryInterval(baseInterval: TimeInterval, connected: Bool) -> TimeInterval {
        connected ? max(60, baseInterval) : baseInterval
    }

    @Published var devices: [YeelightDevice] = []
    @Published var selectedDeviceID: String?
    @Published var status: AppConnectionStatus = .idle
    @Published var brightness: Double = 50
    @Published var colorTemperature: Double = 4000
    @Published var selectedColor = Color(yeelightRGB: 0xFFFFFF)
    @Published var isColorEditingActive = false
    @Published var isPowerOn = false
    @Published var transitionDuration = 500
    @Published var discoveryRetryInterval = 15.0
    @Published var launchAtLogin = false
    @Published var launchAtLoginRequiresApproval = false
    @Published var discoveredCandidates: [DiscoveryCandidate] = []
    @Published var manualHost = ""
    @Published var manualPort = "55443"
    @Published var menuBarIconStyle: MenuBarIconStyle = .connectionStatus
    @Published var defaultManualPort: UInt16 = 55443
    @Published var commandTimeout = 5.0
    @Published var reconnectInterval = 2.0
    @Published var brightnessDebounceMilliseconds = 180
    @Published var colorDebounceMilliseconds = 180
    @Published var popoverWidth = 340.0
    @Published var controlDisplayMode: ControlDisplayMode = .detailed
    @Published var showColorControl = true
    @Published var debugLoggingEnabled = false
    @Published var lastDiscoveryAt: Date?
    @Published var diagnosticEvents: [String] = []
    @Published var customPresets: [LightPreset] = [] {
        didSet {
            rebuildPresetSnapshot()
        }
    }
    @Published var favoritePresetIDs: [String] = LightPreset.defaultFavoriteIDs {
        didSet {
            rebuildPresetSnapshot()
        }
    }
    @Published var selectedPresetID: String = LightPreset.reading.id
    @Published var lightControlMode: LightControlMode = .white
    @Published var shortcutsEnabled = true
    @Published var keyboardShortcuts: [ConfiguredShortcut] = ConfiguredShortcut.defaultSet
    @Published var presetShortcuts: [PresetShortcut] = []
    @Published var shortcutBrightnessStep = 10
    @Published var shortcutRegistrationStatuses: [KeyboardShortcutAction: HotKeyRegistrationStatus] = [:]
    @Published var presetShortcutRegistrationStatuses: [UUID: HotKeyRegistrationStatus] = [:]
    @Published private var presetSnapshot = PresetSnapshot.empty
    @Published private var deviceViewSnapshot = DeviceViewSnapshot.empty

    private let store: DeviceStore
    private let hotKeyManager: GlobalHotKeyManaging
    private let preferenceSaveScheduler: PreferenceSaveScheduler
    private let launchAtLoginManager: LaunchAtLoginManaging
    private lazy var discoveryService = DiscoveryService(
        onDeviceFound: { [weak self] device, sourceHost in
            self?.handleDiscovered(device, sourceHost: sourceHost)
        },
        onError: { [weak self] error in
            self?.status = .error(error.localizedDescription)
        },
        onRejectedPacket: { [weak self] reason in
            self?.recordDiagnostic("Rejected discovery packet: \(reason)", level: .debug)
        }
    )
    private let rateLimiter = CommandRateLimiter()
    private let colorPanelCoordinator = ColorPanelCoordinator()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "io.github.bekircem.yeelightbar", category: "AppState")
    private var connectionSession: ConnectionSession?
    private var preferences = AppPreferences.defaults
    private var diagnosticRing = DiagnosticRing(capacity: 50)
    private var discoveryTimer: Timer?
    private var notFoundTask: Task<Void, Never>?
    private var powerTask: Task<Void, Never>?
    private var brightnessTask: Task<Void, Never>?
    private var colorTemperatureTask: Task<Void, Never>?
    private var colorTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var presetTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var discoveryCandidateRegistry = DiscoveryCandidateRegistry()
    private var colorRevision = 0
    private var pendingColorRGB: Int?
    private var lastSentBrightness: Int?
    private var lastSentColorTemperature: Int?
    private var lastSentColorCommand: ColorCommandSignature?
    private var isColorPanelActive = false
    private var isConnectionReady = false
    private var isRefreshingState = false
    private var started = false
    private lazy var settingsWindowController = SettingsWindowController(state: self)

    private var isUserColorEditingActive: Bool {
        isColorEditingActive || isColorPanelActive
    }

    private static func makeDefaultHotKeyManager() -> GlobalHotKeyManaging {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return DisabledGlobalHotKeyManager()
        }

        return GlobalHotKeyManager()
    }

    init(
        store: DeviceStore = DeviceStore(),
        hotKeyManager: GlobalHotKeyManaging? = nil,
        preferenceSaveScheduler: PreferenceSaveScheduler? = nil,
        launchAtLoginManager: LaunchAtLoginManaging = SystemLaunchAtLoginManager()
    ) {
        self.store = store
        self.hotKeyManager = hotKeyManager ?? Self.makeDefaultHotKeyManager()
        self.preferenceSaveScheduler = preferenceSaveScheduler ?? PreferenceSaveScheduler { preferences in
            store.save(preferences)
        }
        self.launchAtLoginManager = launchAtLoginManager
        rebuildPresetSnapshot()

        colorPanelCoordinator.onColorChange = { [weak self] nsColor in
            self?.setColor(Color(nsColor))
        }

        colorPanelCoordinator.onPanelClose = { [weak self] in
            self?.handleColorPanelClosed()
        }

        self.hotKeyManager.onTarget = { [weak self] target in
            Task { @MainActor in
                self?.performShortcutTarget(target)
            }
        }
    }

    var menuBarSymbolName: String {
        switch menuBarIconStyle {
        case .connectionStatus:
            return status.symbolName
        case .outline:
            return "lightbulb"
        case .filled:
            return "lightbulb.fill"
        }
    }

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var selectedDevice: YeelightDevice? {
        guard let selectedDeviceID else {
            return nil
        }
        return devices.first { $0.id == selectedDeviceID }
    }

    var selectedDeviceSupportsColor: Bool {
        selectedDevice?.supports(.setRGB) == true || selectedDevice?.supports(.setHSV) == true
    }

    var selectedDeviceSupportsScenes: Bool {
        selectedDevice?.supports(.setScene) == true
    }

    var selectedDeviceSupportsFlow: Bool {
        selectedDevice?.supports(.setScene) == true || selectedDevice?.supports(.startColorFlow) == true
    }

    var selectedDeviceIsFlowing: Bool {
        selectedDevice?.state.flowing == true
    }

    var builtInPresets: [LightPreset] {
        presetSnapshot.builtInPresets
    }

    var availablePresets: [LightPreset] {
        presetSnapshot.availablePresets
    }

    var whitePresets: [LightPreset] {
        presetSnapshot.whitePresets
    }

    var colorPresets: [LightPreset] {
        presetSnapshot.colorPresets
    }

    var flowPresets: [LightPreset] {
        presetSnapshot.flowPresets
    }

    var favoritePresets: [LightPreset] {
        presetSnapshot.favoritePresets
    }

    var selectedPreset: LightPreset? {
        availablePresets.first { $0.id == selectedPresetID } ?? availablePresets.first
    }

    var selectedPresetSummary: String {
        selectedPreset?.summary ?? "No mode selected"
    }

    var selectedFlowPresetID: String {
        if flowPresets.contains(where: { $0.id == selectedPresetID }) {
            return selectedPresetID
        }

        return flowPresets.first?.id ?? selectedPresetID
    }

    var selectedFlowPresetSummary: String {
        flowPresets.first { $0.id == selectedFlowPresetID }?.summary ?? "No flow selected"
    }

    var hasSelectedDevice: Bool {
        selectedDevice != nil
    }

    var currentLightLook: CurrentLightLook? {
        guard let selectedDevice else {
            return nil
        }

        let brightnessValue = Int(brightness.rounded()).clamped(to: 1...100)

        switch selectedDevice.state.colorMode {
        case .colorTemperature:
            return CurrentLightLook(
                value: .colorTemperature(Int(colorTemperature.rounded())),
                brightness: brightnessValue
            )
        case .hsv:
            return CurrentLightLook(
                value: .hsv(
                    hue: selectedDevice.state.hue,
                    saturation: selectedDevice.state.saturation
                ),
                brightness: brightnessValue
            )
        case .rgb, .unknown:
            return CurrentLightLook(
                value: .color(rgb: selectedColor.yeelightRGBValue),
                brightness: brightnessValue
            )
        }
    }

    var canControlSelectedDevice: Bool {
        hasSelectedDevice && isConnectionReady
    }

    var connectionReady: Bool {
        isConnectionReady
    }

    var lastErrorMessage: String {
        guard case .error(let message) = status else {
            return "None"
        }

        return message
    }

    var selectedDeviceEndpoint: String {
        deviceViewSnapshot.endpoint
    }

    var selectedDeviceCapabilitiesText: String {
        deviceViewSnapshot.capabilitiesText
    }

    var lastDiscoveryText: String {
        guard let lastDiscoveryAt else {
            return "Never"
        }

        return lastDiscoveryAt.formatted(date: .abbreviated, time: .standard)
    }

    var canAddManualDevice: Bool {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = UInt16(manualPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return LocalNetworkEndpointPolicy.isAllowedDiscoveryHost(host) && port > 0
    }

    func shortcut(for action: KeyboardShortcutAction) -> ConfiguredShortcut {
        keyboardShortcuts.first { $0.action == action }
            ?? ConfiguredShortcut(action: action, combination: action.defaultCombination, isEnabled: action.defaultCombination != nil)
    }

    func shortcutStatus(for action: KeyboardShortcutAction) -> HotKeyRegistrationStatus {
        shortcutRegistrationStatuses[action] ?? (shortcutsEnabled ? .unassigned : .disabled)
    }

    func presetShortcut(for id: UUID) -> PresetShortcut? {
        presetShortcuts.first { $0.id == id }
    }

    func presetShortcutStatus(for id: UUID) -> HotKeyRegistrationStatus {
        presetShortcutRegistrationStatuses[id] ?? (shortcutsEnabled ? .unassigned : .disabled)
    }

    func presetTitle(for id: String?) -> String {
        guard let id else {
            return "Choose Mode"
        }

        return availablePresets.first { $0.id == id }?.title ?? "Mode Missing"
    }

    func start() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        guard !started else {
            return
        }

        started = true
        applyPreferences(store.load(), reconnect: false)
        updateControlsFromSelectedDevice()

        discover()
        scheduleDiscoveryRetry()
    }

    func discover() {
        performDiscovery(isAutomatic: false)
    }

    private func performDiscovery(isAutomatic: Bool) {
        lastDiscoveryAt = Date()
        discoveryCandidateRegistry.prune()
        discoveredCandidates = discoveryCandidateRegistry.candidates
        recordDiagnostic(isAutomatic ? "Background discovery requested" : "Discovery requested", level: isAutomatic ? .debug : .info)
        status = devices.isEmpty ? .searching : status
        notFoundTask?.cancel()
        Task {
            await discoveryService.start()
            await discoveryService.search()
        }

        notFoundTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 4_000_000_000)
                try Task.checkCancellation()
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.devices.isEmpty, self.discoveredCandidates.isEmpty else {
                    return
                }
                self.status = .notFound
            }
        }
    }

    func selectDevice(id: String?) {
        guard selectedDeviceID != id else {
            connectToSelectedDevice()
            return
        }

        cancelPendingDeviceWork()
        selectedDeviceID = id
        preferences.selectedDeviceID = id
        persist()
        updateControlsFromSelectedDevice()
        connectToSelectedDevice()
    }

    func setPower(_ isOn: Bool) {
        let previousValue = isPowerOn
        isPowerOn = isOn
        powerTask?.cancel()
        powerTask = Task { [weak self] in
            guard let self else {
                return
            }

            let message = await self.sendCommand { commandID, duration in
                .setPower(id: commandID, isOn: isOn, duration: duration)
            }

            if message?.isOKResult == true {
                self.commitSelectedPower(isOn)
            } else if !Task.isCancelled {
                self.isPowerOn = previousValue
                self.refreshSelectedDeviceState()
            }
        }
    }

    func setBrightness(_ value: Double) {
        let previousValue = selectedDevice.map { Double($0.state.brightness) } ?? brightness
        brightness = value.clamped(to: 1...100)
        let debounceDelay = debounceNanoseconds(milliseconds: brightnessDebounceMilliseconds)
        brightnessTask?.cancel()
        brightnessTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            let rounded = Int(self.brightness.rounded()).clamped(to: 1...100)
            guard self.shouldSendBrightness(rounded) else {
                return
            }

            let message = await self.sendCommand { commandID, duration in
                .setBrightness(id: commandID, brightness: rounded, duration: duration)
            }

            if message?.isOKResult == true {
                self.commitSelectedBrightness(rounded)
            } else {
                self.clearLastSentBrightness(rounded)
                if !Task.isCancelled {
                    self.brightness = previousValue
                    self.refreshSelectedDeviceState()
                }
            }
        }
    }

    func setColorTemperature(_ value: Double) {
        let previousValue = selectedDevice.map { Double($0.state.colorTemperature) } ?? colorTemperature
        colorTemperature = value.clamped(to: 1700...6500)
        let debounceDelay = debounceNanoseconds(milliseconds: brightnessDebounceMilliseconds)
        colorTemperatureTask?.cancel()
        colorTemperatureTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }
            let rounded = Int(self.colorTemperature.rounded()).clamped(to: 1700...6500)
            guard self.shouldSendColorTemperature(rounded) else {
                return
            }

            let message = await self.sendCommand { commandID, duration in
                .setColorTemperature(id: commandID, temperature: rounded, duration: duration)
            }

            if message?.isOKResult == true {
                self.commitSelectedColorTemperature(rounded)
            } else {
                self.clearLastSentColorTemperature(rounded)
                if !Task.isCancelled {
                    self.colorTemperature = previousValue
                    self.refreshSelectedDeviceState()
                }
            }
        }
    }

    func setColor(_ color: Color) {
        guard selectedDeviceSupportsColor else {
            return
        }

        selectedColor = color

        guard canControlSelectedDevice else {
            return
        }

        let supportsRGB = selectedDevice?.supports(.setRGB) == true
        let rgb = color.yeelightRGBValue
        let hsv = color.yeelightHSVValue
        let hue = Int(hsv.hue.rounded()).clamped(to: 0...359)
        let saturation = Int((hsv.saturation * 100).rounded()).clamped(to: 0...100)
        let signature: ColorCommandSignature = supportsRGB ? .rgb(rgb) : .hsv(hue: hue, saturation: saturation)
        guard shouldSendColor(signature) else {
            return
        }
        colorRevision += 1
        let revision = colorRevision
        pendingColorRGB = rgb
        let debounceDelay = debounceNanoseconds(milliseconds: colorDebounceMilliseconds)
        colorTask?.cancel()
        colorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }

            let message = await self.sendCommand { commandID, duration in
                if supportsRGB {
                    return .setRGB(id: commandID, rgb: rgb, duration: duration)
                } else {
                    return .setHSV(id: commandID, hue: hue, saturation: saturation, duration: duration)
                }
            }

            if message?.isOKResult == true {
                if supportsRGB {
                    self.commitSelectedColor(rgb, revision: revision)
                } else {
                    self.commitSelectedHueSaturation(hue: hue, saturation: saturation, rgb: rgb, revision: revision)
                }
            } else {
                self.clearLastSentColor(signature)
                self.clearPendingColor(revision: revision)
                self.refreshSelectedDeviceState()
            }
        }
    }

    func setHueSaturation(hue: Double, saturation: Double) {
        guard selectedDeviceSupportsColor else {
            return
        }

        let roundedHue = Int(hue.rounded()).clamped(to: 0...359)
        let roundedSaturation = Int((saturation * 100).rounded()).clamped(to: 0...100)
        let previewColor = Color(yeelightHSV: YeelightHSV(
            hue: Double(roundedHue),
            saturation: Double(roundedSaturation) / 100,
            value: 1
        ))
        let rgb = previewColor.yeelightRGBValue
        selectedColor = previewColor

        guard canControlSelectedDevice else {
            return
        }

        let supportsHSV = selectedDevice?.supports(.setHSV) == true
        let signature: ColorCommandSignature = supportsHSV ? .hsv(hue: roundedHue, saturation: roundedSaturation) : .rgb(rgb)
        guard shouldSendColor(signature) else {
            return
        }
        colorRevision += 1
        let revision = colorRevision
        pendingColorRGB = rgb
        let debounceDelay = debounceNanoseconds(milliseconds: colorDebounceMilliseconds)
        colorTask?.cancel()
        colorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounceDelay)
            guard !Task.isCancelled else {
                return
            }
            guard let self else {
                return
            }

            let message = await self.sendCommand { commandID, duration in
                if supportsHSV {
                    return .setHSV(id: commandID, hue: roundedHue, saturation: roundedSaturation, duration: duration)
                } else {
                    return .setRGB(id: commandID, rgb: rgb, duration: duration)
                }
            }

            if message?.isOKResult == true {
                if supportsHSV {
                    self.commitSelectedHueSaturation(
                        hue: roundedHue,
                        saturation: roundedSaturation,
                        rgb: rgb,
                        revision: revision
                    )
                } else {
                    self.commitSelectedColor(rgb, revision: revision)
                }
            } else {
                self.clearLastSentColor(signature)
                self.clearPendingColor(revision: revision)
                self.refreshSelectedDeviceState()
            }
        }
    }

    func toggleColorEditor() {
        guard selectedDeviceSupportsColor, canControlSelectedDevice else {
            return
        }

        if !isColorEditingActive {
            colorPanelCoordinator.close()
            isColorPanelActive = false
        }

        isColorEditingActive.toggle()

        if !isColorEditingActive, pendingColorRGB == nil {
            updateControlsFromSelectedDevice()
        }
    }

    func closeColorEditor() {
        guard isColorEditingActive else {
            return
        }

        isColorEditingActive = false

        if pendingColorRGB == nil {
            updateControlsFromSelectedDevice()
        }
    }

    func showColorPanel() {
        guard selectedDeviceSupportsColor, canControlSelectedDevice else {
            return
        }

        isColorEditingActive = false
        isColorPanelActive = true
        colorPanelCoordinator.show(color: selectedColor.yeelightNSColor)
    }

    func setLightControlMode(_ mode: LightControlMode) {
        switch mode {
        case .white:
            lightControlMode = .white
            setColorTemperature(colorTemperature)
        case .color:
            guard selectedDeviceSupportsColor else {
                lightControlMode = .white
                return
            }

            lightControlMode = .color
            setColor(selectedColor)
        case .flow:
            lightControlMode = .flow
        }
    }

    func setSelectedPresetID(_ id: String) {
        guard availablePresets.contains(where: { $0.id == id }) else {
            return
        }

        selectedPresetID = id
        preferences.selectedPresetID = id
        persist()
    }

    func applySelectedPreset() {
        guard let selectedPreset else {
            return
        }

        applyPreset(id: selectedPreset.id)
    }

    func applyPreset(id: String) {
        guard let preset = availablePresets.first(where: { $0.id == id }) else {
            return
        }

        selectedPresetID = preset.id
        preferences.selectedPresetID = preset.id
        persist()

        presetTask?.cancel()
        presetTask = Task { [weak self] in
            await self?.applyPreset(preset)
        }
    }

    func stopFlow() {
        guard hasSelectedDevice else {
            status = .offline
            return
        }

        guard selectedDevice?.supports(.stopColorFlow) == true else {
            status = .error("Selected device does not support stopping color flow")
            return
        }

        presetTask?.cancel()
        presetTask = Task { [weak self] in
            guard let self else {
                return
            }

            let message = await self.sendCommand { commandID, _ in
                .stopColorFlow(id: commandID)
            }

            if message?.isOKResult == true {
                self.commitFlowStopped()
                self.refreshSelectedDeviceState()
            }
        }
    }

    @discardableResult
    func saveCurrentMode(named rawName: String) -> LightPreset? {
        let title = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            status = .error("Enter a mode name")
            return nil
        }

        guard let currentLightLook else {
            status = .error("Select a bulb before saving a mode")
            return nil
        }

        let preset = currentLightLook.makePreset(
            id: "custom-mode-\(UUID().uuidString)",
            title: title
        )
        upsertCustomPreset(preset)
        selectedPresetID = preset.id
        preferences.selectedPresetID = preset.id
        persist()
        recordDiagnostic("Saved mode \(title)")
        return preset
    }

    @discardableResult
    func saveCustomFlow(named rawName: String, flow: ColorFlow) -> LightPreset? {
        let title = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            status = .error("Enter a flow name")
            return nil
        }

        let sanitized = flow.sanitized
        guard sanitized.isValid else {
            status = .error("Add at least one flow step")
            return nil
        }

        let preset = LightPreset(
            id: "custom-flow-\(UUID().uuidString)",
            title: title,
            kind: .flow,
            flow: sanitized
        )
        upsertCustomPreset(preset)
        selectedPresetID = preset.id
        preferences.selectedPresetID = preset.id
        persist()
        recordDiagnostic("Saved flow \(title)")
        return preset
    }

    func removeCustomPreset(id: String) {
        guard customPresets.contains(where: { $0.id == id }) else {
            return
        }

        customPresets.removeAll { $0.id == id }
        favoritePresetIDs.removeAll { $0 == id }

        if selectedPresetID == id {
            selectedPresetID = LightPreset.reading.id
        }

        preferences.customPresets = customPresets
        preferences.favoritePresetIDs = favoritePresetIDs
        preferences.selectedPresetID = selectedPresetID
        persist()
    }

    func toggleFavoritePreset(id: String) {
        guard availablePresets.contains(where: { $0.id == id }) else {
            return
        }

        if favoritePresetIDs.contains(id) {
            favoritePresetIDs.removeAll { $0 == id }
        } else {
            favoritePresetIDs.append(id)
        }

        preferences.favoritePresetIDs = favoritePresetIDs
        persist()
    }

    func resetCustomPresets() {
        customPresets = []
        favoritePresetIDs = LightPreset.defaultFavoriteIDs
        selectedPresetID = LightPreset.reading.id
        preferences.customPresets = customPresets
        preferences.favoritePresetIDs = favoritePresetIDs
        preferences.selectedPresetID = selectedPresetID
        persist()
        recordDiagnostic("Custom modes reset")
    }

    func setTransitionDuration(_ duration: Int) {
        transitionDuration = duration.clamped(to: 30...5000)
        preferences.transitionDuration = transitionDuration
        persist()
    }

    func setDiscoveryRetryInterval(_ interval: Double) {
        discoveryRetryInterval = interval.clamped(to: 5...120)
        preferences.discoveryRetryInterval = discoveryRetryInterval
        persist()
        scheduleDiscoveryRetry()
    }

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        menuBarIconStyle = style
        preferences.menuBarIconStyle = style
        persist()
    }

    func setDefaultManualPort(_ port: UInt16) {
        let previousPort = defaultManualPort
        defaultManualPort = port.clamped(to: 1...65535)
        preferences.defaultManualPort = defaultManualPort

        let trimmedManualPort = manualPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedManualPort.isEmpty || trimmedManualPort == String(previousPort) {
            manualPort = String(defaultManualPort)
        }

        persist()
    }

    func setCommandTimeout(_ timeout: Double) {
        commandTimeout = timeout.clamped(to: 1...30)
        preferences.commandTimeout = commandTimeout
        persist()
    }

    func setReconnectInterval(_ interval: Double) {
        reconnectInterval = interval.clamped(to: 1...60)
        preferences.reconnectInterval = reconnectInterval
        persist()
    }

    func setBrightnessDebounceMilliseconds(_ milliseconds: Int) {
        brightnessDebounceMilliseconds = milliseconds.clamped(to: 30...1000)
        preferences.brightnessDebounceMilliseconds = brightnessDebounceMilliseconds
        persist()
    }

    func setColorDebounceMilliseconds(_ milliseconds: Int) {
        colorDebounceMilliseconds = milliseconds.clamped(to: 30...1000)
        preferences.colorDebounceMilliseconds = colorDebounceMilliseconds
        persist()
    }

    func setPopoverWidth(_ width: Double) {
        popoverWidth = width.clamped(to: 300...520)
        preferences.popoverWidth = popoverWidth
        persist()
    }

    func setControlDisplayMode(_ mode: ControlDisplayMode) {
        controlDisplayMode = mode
        preferences.controlDisplayMode = mode
        persist()
    }

    func setShowColorControl(_ shouldShow: Bool) {
        showColorControl = shouldShow
        preferences.showColorControl = shouldShow
        persist()
    }

    func setShortcutsEnabled(_ enabled: Bool) {
        shortcutsEnabled = enabled
        preferences.shortcutsEnabled = enabled
        persist()
        applyHotKeyRegistrations()
    }

    func setShortcutBrightnessStep(_ step: Int) {
        shortcutBrightnessStep = step.clamped(to: 1...25)
        preferences.shortcutBrightnessStep = shortcutBrightnessStep
        persist()
    }

    func assignShortcut(action: KeyboardShortcutAction, combination: HotKeyCombination) -> Bool {
        if let validationError = combination.validationError {
            shortcutRegistrationStatuses[action] = .invalid(validationError)
            recordDiagnostic("Shortcut \(action.title) invalid: \(validationError)", level: .error)
            return false
        }

        if let message = duplicateShortcutMessage(for: combination, excludingAction: action) {
            shortcutRegistrationStatuses[action] = .invalid(message)
            recordDiagnostic("Shortcut \(action.title) invalid: \(message)", level: .error)
            return false
        }

        upsertShortcut(ConfiguredShortcut(action: action, combination: combination, isEnabled: true))
        persist()
        applyHotKeyRegistrations()
        return true
    }

    func clearShortcut(action: KeyboardShortcutAction) {
        upsertShortcut(ConfiguredShortcut(action: action, combination: nil, isEnabled: false))
        persist()
        applyHotKeyRegistrations()
    }

    func resetShortcutsToDefaults() {
        keyboardShortcuts = ConfiguredShortcut.defaultSet
        presetShortcuts = []
        shortcutBrightnessStep = AppPreferences.defaults.shortcutBrightnessStep
        preferences.keyboardShortcuts = keyboardShortcuts
        preferences.presetShortcuts = presetShortcuts
        preferences.shortcutBrightnessStep = shortcutBrightnessStep
        preferences.shortcutsEnabled = shortcutsEnabled
        persist()
        applyHotKeyRegistrations()
    }

    @discardableResult
    func addPresetShortcut() -> UUID {
        let shortcut = PresetShortcut()
        presetShortcuts.append(shortcut)
        preferences.presetShortcuts = presetShortcuts
        persist()
        applyHotKeyRegistrations()
        return shortcut.id
    }

    func deletePresetShortcut(id: UUID) {
        presetShortcuts.removeAll { $0.id == id }
        presetShortcutRegistrationStatuses.removeValue(forKey: id)
        preferences.presetShortcuts = presetShortcuts
        persist()
        applyHotKeyRegistrations()
    }

    func setPresetShortcutPreset(id: UUID, presetID: String?) {
        let normalizedPresetID = presetID?.isEmpty == true ? nil : presetID
        if let normalizedPresetID,
           !availablePresets.contains(where: { $0.id == normalizedPresetID }) {
            presetShortcutRegistrationStatuses[id] = .missingPreset
            return
        }

        updatePresetShortcut(id: id) { shortcut in
            shortcut.presetID = normalizedPresetID
            shortcut.isEnabled = shortcut.combination != nil
        }
        persist()
        applyHotKeyRegistrations()
    }

    func assignPresetShortcut(id: UUID, combination: HotKeyCombination) -> Bool {
        if let validationError = combination.validationError {
            presetShortcutRegistrationStatuses[id] = .invalid(validationError)
            recordDiagnostic("Direct mode shortcut invalid: \(validationError)", level: .error)
            return false
        }

        if let message = duplicateShortcutMessage(for: combination, excludingPresetShortcutID: id) {
            presetShortcutRegistrationStatuses[id] = .invalid(message)
            recordDiagnostic("Direct mode shortcut invalid: \(message)", level: .error)
            return false
        }

        updatePresetShortcut(id: id) { shortcut in
            shortcut.combination = combination
            shortcut.isEnabled = true
        }
        persist()
        applyHotKeyRegistrations()
        return true
    }

    func clearPresetShortcut(id: UUID) {
        updatePresetShortcut(id: id) { shortcut in
            shortcut.combination = nil
            shortcut.isEnabled = false
        }
        persist()
        applyHotKeyRegistrations()
    }

    func beginShortcutRecording() {
        hotKeyManager.unregisterAll()
    }

    func endShortcutRecording() {
        applyHotKeyRegistrations()
    }

    func setDebugLoggingEnabled(_ enabled: Bool) {
        debugLoggingEnabled = enabled
        preferences.debugLoggingEnabled = enabled
        persist()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            reconcileLaunchAtLoginState()
            preferences.launchAtLogin = launchAtLogin
            persist()
        } catch {
            reconcileLaunchAtLoginState()
            status = .error("Launch at Login could not be changed: \(sanitizedRemoteMessage(error.localizedDescription))")
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func forgetDevices() {
        cancelColorSelection()
        devices = []
        selectedDeviceID = nil
        preferences.savedDevices = []
        preferences.selectedDeviceID = nil
        persist()
        disconnectCurrentConnection()
        status = .idle
    }

    func removeSelectedDevice() {
        guard let selectedDeviceID else {
            return
        }

        cancelColorSelection()
        disconnectCurrentConnection()
        devices.removeAll { $0.id == selectedDeviceID }
        self.selectedDeviceID = devices.first?.id
        preferences.savedDevices = devices
        preferences.selectedDeviceID = self.selectedDeviceID
        persist()
        updateControlsFromSelectedDevice()

        if self.selectedDeviceID == nil {
            status = .idle
        } else {
            connectToSelectedDevice()
        }
    }

    func addManualDevice() {
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = manualPort.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else {
            status = .error("Enter the bulb IP address")
            return
        }

        guard LocalNetworkEndpointPolicy.isAllowedDiscoveryHost(host) else {
            status = .error("Enter a private or link-local IP address")
            return
        }

        guard let port = UInt16(portText), port > 0 else {
            status = .error("Enter a valid port")
            return
        }

        if let existing = devices.first(where: { $0.host == host && $0.port == port }) {
            selectDevice(id: existing.id)
            return
        }

        cancelColorSelection()
        let device = YeelightDevice(
            id: "manual-\(host):\(port)",
            name: "Yeelight \(host)",
            model: "manual",
            host: host,
            port: port,
            capabilities: Set(YeelightMethod.allCases.map(\.rawValue)),
            state: .unknown,
            lastSeen: Date()
        )

        devices.append(device)
        devices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        selectedDeviceID = device.id
        preferences.savedDevices = devices
        preferences.selectedDeviceID = device.id
        persist()
        updateControlsFromSelectedDevice()
        connectToSelectedDevice()
    }

    func showSettings() {
        settingsWindowController.show()
    }

    func checkForUpdates() {
        guard let url = URL(string: "https://github.com/bekircem/YeelightBar/releases") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func refreshSelectedDeviceStateForUser() {
        recordDiagnostic("Manual state refresh requested")
        refreshSelectedDeviceState()
    }

    func testSelectedDeviceConnection() {
        guard hasSelectedDevice else {
            status = .offline
            recordDiagnostic("Test command skipped: no selected device")
            return
        }

        recordDiagnostic("Test command requested")
        Task { [weak self] in
            let message = await self?.sendCommand { commandID, _ in
                .getProperties(id: commandID, ["power"])
            }

            await MainActor.run {
                if message == nil {
                    self?.recordDiagnostic("Test command failed", level: .error)
                } else {
                    self?.recordDiagnostic("Test command completed")
                }
            }
        }
    }

    func clearDiagnosticsLog() {
        diagnosticEvents = diagnosticRing.removeAll()
    }

    func performShortcutTarget(_ target: KeyboardShortcutTarget) {
        switch target {
        case .action(let action):
            performShortcutAction(action)
        case .presetShortcut(let id):
            performPresetShortcut(id: id)
        }
    }

    func performShortcutAction(_ action: KeyboardShortcutAction) {
        guard shortcutsEnabled else {
            return
        }

        guard canControlSelectedDevice else {
            recordDiagnostic("Shortcut \(action.title) skipped: no connected selected device")
            return
        }

        switch action {
        case .togglePower:
            setPower(!isPowerOn)
        case .cycleWhiteColorMode:
            if lightControlMode == .white {
                guard selectedDeviceSupportsColor else {
                    recordDiagnostic("Shortcut \(action.title) skipped: selected device has no color support")
                    return
                }
                setLightControlMode(.color)
            } else {
                setLightControlMode(.white)
            }
        case .nextFavoritePreset:
            applyFavoritePreset(offset: 1)
        case .previousFavoritePreset:
            applyFavoritePreset(offset: -1)
        case .brightnessUp:
            setBrightness((brightness + Double(shortcutBrightnessStep)).clamped(to: 1...100))
        case .brightnessDown:
            setBrightness((brightness - Double(shortcutBrightnessStep)).clamped(to: 1...100))
        case .stopFlow:
            guard selectedDeviceIsFlowing else {
                recordDiagnostic("Shortcut \(action.title) skipped: no flow is running")
                return
            }
            stopFlow()
        }
    }

    private func performPresetShortcut(id: UUID) {
        guard shortcutsEnabled else {
            return
        }

        guard canControlSelectedDevice else {
            recordDiagnostic("Direct mode shortcut skipped: no connected selected device")
            return
        }

        guard let shortcut = presetShortcuts.first(where: { $0.id == id }) else {
            recordDiagnostic("Direct mode shortcut skipped: shortcut not found")
            return
        }

        guard let presetID = shortcut.presetID,
              availablePresets.contains(where: { $0.id == presetID }) else {
            recordDiagnostic("Direct mode shortcut skipped: mode missing")
            return
        }

        applyPreset(id: presetID)
    }

    func resetPreferences() {
        cancelColorSelection()
        disconnectCurrentConnection()

        var launchAtLoginError: Error?
        if launchAtLogin || launchAtLoginRequiresApproval {
            do {
                try launchAtLoginManager.setEnabled(false)
            } catch {
                launchAtLoginError = error
            }
        }

        store.clear()
        applyPreferences(.defaults, reconnect: false)
        manualHost = ""
        if let launchAtLoginError {
            status = .error("Preferences were reset, but Launch at Login could not be disabled: \(sanitizedRemoteMessage(launchAtLoginError.localizedDescription))")
        } else {
            status = .idle
        }
        updateControlsFromSelectedDevice()
        persist()
        recordDiagnostic("Preferences reset")
    }

    func exportPreferences() {
        let panel = NSSavePanel()
        panel.title = "Export YeelightBar Settings"
        panel.nameFieldStringValue = "YeelightBar Settings.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                do {
                    let data = try self.encodedPreferences()
                    try data.write(to: url, options: .atomic)
                    self.recordDiagnostic("Preferences exported")
                } catch {
                    self.status = .error(error.localizedDescription)
                    self.recordDiagnostic("Export failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func importPreferences() {
        let panel = NSOpenPanel()
        panel.title = "Import YeelightBar Settings"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                return
            }

            Task { @MainActor in
                guard let self else {
                    return
                }

                do {
                    let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard resourceValues.isRegularFile == true else {
                        throw CocoaError(.fileReadUnsupportedScheme)
                    }
                    guard (resourceValues.fileSize ?? 0) <= 5 * 1024 * 1024 else {
                        throw PreferencesImportError.fileTooLarge
                    }

                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    let imported = try await Task.detached(priority: .userInitiated) {
                        try Self.decodeImportedPreferences(data)
                    }.value

                    let alert = NSAlert()
                    alert.messageText = "Import YeelightBar Settings?"
                    alert.informativeText = "This will replace your current settings with \(imported.savedDevices.count) devices, \(imported.customPresets.count) custom modes, and \(imported.presetShortcuts.count) direct shortcuts."
                    alert.addButton(withTitle: "Import")
                    alert.addButton(withTitle: "Cancel")
                    guard alert.runModal() == .alertFirstButtonReturn else {
                        return
                    }

                    self.applyImportedPreferences(imported)
                    self.recordDiagnostic("Preferences imported")
                } catch {
                    self.status = .error(error.localizedDescription)
                    self.recordDiagnostic("Import failed: \(error.localizedDescription)", level: .error)
                }
            }
        }
    }

    func quit() {
        preferenceSaveScheduler.flushPending()
        NSApplication.shared.terminate(nil)
    }

    private func upsertShortcut(_ shortcut: ConfiguredShortcut) {
        if let index = keyboardShortcuts.firstIndex(where: { $0.action == shortcut.action }) {
            keyboardShortcuts[index] = shortcut
        } else {
            keyboardShortcuts.append(shortcut)
        }

        keyboardShortcuts.sort { $0.action.hotKeyID < $1.action.hotKeyID }
        preferences.keyboardShortcuts = keyboardShortcuts
    }

    private func updatePresetShortcut(id: UUID, mutate: (inout PresetShortcut) -> Void) {
        guard let index = presetShortcuts.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&presetShortcuts[index])
        preferences.presetShortcuts = presetShortcuts
    }

    private func duplicateShortcutMessage(
        for combination: HotKeyCombination,
        excludingAction: KeyboardShortcutAction? = nil,
        excludingPresetShortcutID: UUID? = nil
    ) -> String? {
        if let duplicate = keyboardShortcuts.first(where: {
            $0.action != excludingAction && $0.isEnabled && $0.combination == combination
        }) {
            return "Duplicate of \(duplicate.action.title)."
        }

        if presetShortcuts.contains(where: {
            $0.id != excludingPresetShortcutID && $0.isEnabled && $0.combination == combination
        }) {
            return "Duplicate of Direct Mode Shortcut."
        }

        return nil
    }

    private func applyFavoritePreset(offset: Int) {
        let presets = favoritePresets
        guard !presets.isEmpty else {
            recordDiagnostic("Favorite shortcut skipped: no favorites")
            return
        }

        let currentIndex = presets.firstIndex { $0.id == selectedPresetID } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (currentIndex + offset + presets.count) % presets.count
        applyPreset(id: presets[nextIndex].id)
    }

    private func applyHotKeyRegistrations() {
        let result = hotKeyManager.apply(
            shortcuts: keyboardShortcuts,
            presetShortcuts: presetShortcuts,
            availablePresetIDs: Set(availablePresets.map(\.id)),
            enabled: shortcutsEnabled
        )
        shortcutRegistrationStatuses = result.actionStatuses
        presetShortcutRegistrationStatuses = result.presetShortcutStatuses

        for action in KeyboardShortcutAction.allCases {
            guard let status = result.actionStatuses[action] else {
                continue
            }

            switch status {
            case .conflict, .invalid, .failed, .missingPreset:
                let detail = status.detail.map { ": \($0)" } ?? ""
                recordDiagnostic("Shortcut \(action.title) \(status.title.lowercased())\(detail)")
            case .disabled, .unassigned, .registered:
                break
            }
        }

        for shortcut in presetShortcuts {
            guard let status = result.presetShortcutStatuses[shortcut.id] else {
                continue
            }

            switch status {
            case .conflict, .invalid, .failed, .missingPreset:
                let modeTitle = presetTitle(for: shortcut.presetID)
                let detail = status.detail.map { ": \($0)" } ?? ""
                recordDiagnostic("Direct mode shortcut \(modeTitle) \(status.title.lowercased())\(detail)")
            case .disabled, .unassigned, .registered:
                break
            }
        }
    }

    private func applyPreset(_ preset: LightPreset) async {
        guard hasSelectedDevice else {
            status = .offline
            return
        }

        cancelColorSelection()

        guard canControlSelectedDevice else {
            status = .offline
            return
        }

        recordDiagnostic("Applying mode \(preset.title)")

        switch preset.kind {
        case .color:
            await applyStaticPreset(preset)
        case .colorTemperature:
            await applyStaticPreset(preset)
        case .hsv:
            await applyStaticPreset(preset)
        case .flow:
            await applyFlowPreset(preset)
        }
    }

    private func applyStaticPreset(_ preset: LightPreset) async {
        let supportsScene = selectedDevice?.supports(.setScene) == true
        var applied = false

        if supportsScene {
            let message = await sendCommand { commandID, _ in
                switch preset.kind {
                case .color:
                    return .setSceneColor(id: commandID, rgb: preset.rgb, brightness: preset.brightness)
                case .colorTemperature:
                    return .setSceneColorTemperature(
                        id: commandID,
                        temperature: preset.colorTemperature,
                        brightness: preset.brightness
                    )
                case .hsv:
                    return .setSceneHSV(
                        id: commandID,
                        hue: preset.hue,
                        saturation: preset.saturation,
                        brightness: preset.brightness
                    )
                case .flow:
                    return .setSceneColor(id: commandID, rgb: preset.rgb, brightness: preset.brightness)
                }
            }
            applied = message?.isOKResult == true
        } else {
            applied = await applyStaticPresetFallback(preset)
        }

        if applied {
            commitAppliedPreset(preset)
            refreshSelectedDeviceState()
        } else {
            refreshSelectedDeviceState()
        }
    }

    private func applyStaticPresetFallback(_ preset: LightPreset) async -> Bool {
        let powerMessage = await sendCommand { commandID, duration in
            .setPower(id: commandID, isOn: true, duration: duration)
        }

        guard powerMessage?.isOKResult == true else {
            return false
        }

        switch preset.kind {
        case .color:
            let colorMessage = await sendCommand { commandID, duration in
                .setRGB(id: commandID, rgb: preset.rgb, duration: duration)
            }
            guard colorMessage?.isOKResult == true else {
                return false
            }
        case .colorTemperature:
            let temperatureMessage = await sendCommand { commandID, duration in
                .setColorTemperature(id: commandID, temperature: preset.colorTemperature, duration: duration)
            }
            guard temperatureMessage?.isOKResult == true else {
                return false
            }
        case .hsv:
            let hsvMessage = await sendCommand { commandID, duration in
                .setHSV(id: commandID, hue: preset.hue, saturation: preset.saturation, duration: duration)
            }
            guard hsvMessage?.isOKResult == true else {
                return false
            }
        case .flow:
            return false
        }

        let brightnessMessage = await sendCommand { commandID, duration in
            .setBrightness(id: commandID, brightness: preset.brightness, duration: duration)
        }
        return brightnessMessage?.isOKResult == true
    }

    private func applyFlowPreset(_ preset: LightPreset) async {
        guard let flow = preset.flow?.sanitized, flow.isValid else {
            status = .error("Selected flow is invalid")
            return
        }

        var applied = false

        if selectedDevice?.supports(.setScene) == true {
            let message = await sendCommand { commandID, _ in
                .setSceneColorFlow(id: commandID, flow: flow)
            }
            applied = message?.isOKResult == true
        } else if selectedDevice?.supports(.startColorFlow) == true {
            let powerMessage = await sendCommand { commandID, duration in
                .setPower(id: commandID, isOn: true, duration: duration)
            }

            if powerMessage?.isOKResult == true {
                let flowMessage = await sendCommand { commandID, _ in
                    .startColorFlow(id: commandID, flow: flow)
                }
                applied = flowMessage?.isOKResult == true
            }
        } else {
            status = .error("Selected device does not support color flow")
        }

        if applied {
            commitAppliedPreset(preset)
            refreshSelectedDeviceState()
        } else {
            refreshSelectedDeviceState()
        }
    }

    private func handleDiscovered(_ device: YeelightDevice, sourceHost: String) {
        let now = Date()
        guard discoveryCandidateRegistry.acceptsPacket(from: sourceHost, at: now) else {
            recordDiagnostic("Discovery source rate limit reached", level: .debug)
            return
        }

        recordDiagnostic("Discovered local device", level: .debug)

        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            let endpointChanged = devices[index].host != device.host || devices[index].port != device.port
            if !endpointChanged {
                devices[index] = mergeDevice(existing: devices[index], discovered: device)
                preferences.savedDevices = devices
                if selectedDeviceID == device.id {
                    updateControlsFromSelectedDevice()
                    if status != .connected {
                        connectToSelectedDevice()
                    }
                }
                persistDeferred()
                return
            }

            discoveryCandidateRegistry.upsert(
                DiscoveryCandidate(
                    device: device,
                    sourceHost: sourceHost,
                    discoveredAt: now,
                    endpointChanged: true
                ),
                at: now
            )
        } else {
            discoveryCandidateRegistry.upsert(
                DiscoveryCandidate(
                    device: device,
                    sourceHost: sourceHost,
                    discoveredAt: now,
                    endpointChanged: false
                ),
                at: now
            )
        }
        discoveredCandidates = discoveryCandidateRegistry.candidates

        if status == .searching || status == .notFound {
            status = .idle
        }
    }

    func trustDiscoveredCandidate(id: String) {
        guard let candidate = discoveredCandidates.first(where: { $0.id == id }) else {
            return
        }

        cancelPendingDeviceWork()
        if let index = devices.firstIndex(where: { $0.id == candidate.device.id }) {
            devices[index] = mergeDevice(existing: devices[index], discovered: candidate.device)
        } else {
            devices.append(candidate.device)
        }
        devices.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        discoveryCandidateRegistry.remove(deviceID: candidate.device.id)
        discoveredCandidates = discoveryCandidateRegistry.candidates
        selectedDeviceID = candidate.device.id
        preferences.savedDevices = devices
        preferences.selectedDeviceID = selectedDeviceID
        persist()
        updateControlsFromSelectedDevice()
        connectToSelectedDevice()
    }

    func dismissDiscoveredCandidate(id: String) {
        discoveryCandidateRegistry.remove(candidateID: id)
        discoveredCandidates = discoveryCandidateRegistry.candidates
    }

    private func mergeDevice(existing: YeelightDevice, discovered: YeelightDevice) -> YeelightDevice {
        var merged = discovered
        if discovered.name.isEmpty {
            merged.name = existing.name
        }
        return merged
    }

    private func connectToSelectedDevice() {
        disconnectCurrentConnection()

        guard let selectedDevice else {
            status = devices.isEmpty ? .notFound : .idle
            return
        }

        let sessionID = UUID()
        let deviceID = selectedDevice.id
        let newConnection = YeelightConnection(
            onNotification: { [weak self] properties in
                self?.handleSessionNotification(properties, sessionID: sessionID, deviceID: deviceID)
            },
            onStateChanged: { [weak self] state in
                self?.handleConnectionState(state, sessionID: sessionID, deviceID: deviceID)
            }
        )
        connectionSession = ConnectionSession(id: sessionID, deviceID: deviceID, connection: newConnection)
        status = .searching
        Task {
            await newConnection.connect(to: selectedDevice)
        }
    }

    private func disconnectCurrentConnection() {
        cancelPendingDeviceWork()
        isConnectionReady = false
        resetLastSentControlSignatures()
        let oldSession = connectionSession
        connectionSession = nil
        Task {
            await oldSession?.connection.disconnect()
        }
    }

    private func handleSessionNotification(_ properties: [String: String], sessionID: UUID, deviceID: String) {
        guard sessionIsActive(id: sessionID, deviceID: deviceID) else {
            return
        }
        applyNotification(properties)
    }

    private func handleConnectionState(_ state: NWConnection.State, sessionID: UUID, deviceID: String) {
        guard sessionIsActive(id: sessionID, deviceID: deviceID) else {
            return
        }

        switch state {
        case .ready:
            isConnectionReady = true
            scheduleDiscoveryRetry()
            status = .connected
            recordDiagnostic("Connected to selected bulb")
            refreshSelectedDeviceState()
        case .failed(let error):
            isConnectionReady = false
            scheduleDiscoveryRetry()
            recordDiagnostic("Connection failed: \(sanitizedRemoteMessage(error.localizedDescription))", level: .error)
            markSelectedDeviceOffline(message: "Cannot connect to the selected bulb.")
            scheduleReconnect(sessionID: sessionID, deviceID: deviceID)
        case .cancelled:
            isConnectionReady = false
            scheduleDiscoveryRetry()
            recordDiagnostic("Connection cancelled")
            markSelectedDeviceOffline()
            scheduleReconnect(sessionID: sessionID, deviceID: deviceID)
        case .waiting(let error):
            isConnectionReady = false
            scheduleDiscoveryRetry()
            recordDiagnostic("Connection waiting: \(sanitizedRemoteMessage(error.localizedDescription))", level: .error)
            markSelectedDeviceOffline(message: "Waiting for the selected bulb.")
        default:
            break
        }
    }

    private func scheduleReconnect(sessionID: UUID, deviceID: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            let seconds = await MainActor.run {
                self?.reconnectInterval ?? AppPreferences.defaults.reconnectInterval
            }
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds.clamped(to: 1...60) * 1_000_000_000))
                try Task.checkCancellation()
            } catch {
                return
            }
            await MainActor.run {
                guard let self, self.sessionIsActive(id: sessionID, deviceID: deviceID) else {
                    return
                }
                self.connectToSelectedDevice()
            }
        }
    }

    private func refreshSelectedDeviceState() {
        guard !isRefreshingState else {
            return
        }

        isRefreshingState = true
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            _ = await self?.sendCommand { commandID, _ in
                .getProperties(id: commandID, Self.statePropertyKeys)
            }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                self?.isRefreshingState = false
            }
        }
    }

    private func sendCommand(_ builder: @escaping @Sendable (Int, Int) -> YeelightCommand) async -> YeelightIncomingMessage? {
        guard let session = connectionSession else {
            status = .offline
            return nil
        }

        do {
            try await rateLimiter.waitTurn(connectionID: session.id)
            try Task.checkCancellation()
            guard sessionIsActive(id: session.id, deviceID: session.deviceID) else {
                return nil
            }

            let commandID = await session.connection.nextCommandID()
            let command = builder(commandID, transitionDuration)
            let message = try await session.connection.send(command, timeout: commandTimeout)
            guard sessionIsActive(id: session.id, deviceID: session.deviceID) else {
                return nil
            }
            applyIncomingMessage(message)
            return message
        } catch is CancellationError {
            return nil
        } catch {
            guard sessionIsActive(id: session.id, deviceID: session.deviceID) else {
                return nil
            }
            status = .error(error.localizedDescription)
            recordDiagnostic("Command failed: \(sanitizedRemoteMessage(error.localizedDescription))", level: .error)
            return nil
        }
    }

    private func sessionIsActive(id: UUID, deviceID: String) -> Bool {
        connectionSession?.id == id
            && connectionSession?.deviceID == deviceID
            && selectedDeviceID == deviceID
    }

    private func applyIncomingMessage(_ message: YeelightIncomingMessage) {
        switch message {
        case .result(_, let values):
            if values.isOKResult {
                if isConnectionReady {
                    status = .connected
                }
                return
            }

            applyGetPropResult(values)
        case .failure(_, let error):
            let safeMessage = sanitizedRemoteMessage(error.message)
            status = .error(safeMessage)
            recordDiagnostic("Device error: \(safeMessage)", level: .error)
            refreshSelectedDeviceState()
        case .notification(let properties):
            applyNotification(properties)
        }
    }

    private func applyGetPropResult(_ values: [YeelightValue]) {
        guard let index = selectedDeviceIndex else {
            return
        }

        var properties: [String: String] = [:]

        for (key, value) in zip(Self.statePropertyKeys, values) {
            properties[key] = value.stringValue
        }

        devices[index].state.apply(properties: properties)
        devices[index].state.online = true
        if isConnectionReady {
            status = .connected
        }
        updateControlsFromSelectedDevice()
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func applyNotification(_ properties: [String: String]) {
        guard let index = selectedDeviceIndex else {
            return
        }

        let allowedKeys = Set(Self.statePropertyKeys)
        let sanitizedProperties = properties.reduce(into: [String: String]()) { result, entry in
            guard allowedKeys.contains(entry.key) else { return }
            result[entry.key] = String(sanitizedRemoteMessage(entry.value).prefix(256))
        }
        devices[index].state.apply(properties: sanitizedProperties)
        devices[index].state.online = true
        if isConnectionReady {
            status = .connected
        }
        updateControlsFromSelectedDevice()
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitSelectedPower(_ isOn: Bool) {
        guard let index = selectedDeviceIndex else {
            return
        }

        devices[index].state.power = isOn ? .on : .off
        devices[index].state.online = true
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitSelectedBrightness(_ brightness: Int) {
        guard let index = selectedDeviceIndex else {
            return
        }

        devices[index].state.brightness = brightness.clamped(to: 1...100)
        devices[index].state.online = true
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitSelectedColorTemperature(_ colorTemperature: Int) {
        guard let index = selectedDeviceIndex else {
            return
        }

        devices[index].state.colorTemperature = colorTemperature.clamped(to: 1700...6500)
        devices[index].state.colorMode = .colorTemperature
        devices[index].state.flowing = false
        devices[index].state.flowParameters = ""
        devices[index].state.online = true
        lightControlMode = .white
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitSelectedColor(_ rgb: Int, revision: Int) {
        guard revision == colorRevision, let index = selectedDeviceIndex else {
            return
        }

        pendingColorRGB = nil
        devices[index].state.rgb = rgb.clamped(to: 0...0xFFFFFF)
        devices[index].state.colorMode = .rgb
        devices[index].state.flowing = false
        devices[index].state.flowParameters = ""
        devices[index].state.online = true
        selectedColor = Color(yeelightRGB: rgb)
        lightControlMode = .color
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitSelectedHueSaturation(hue: Int, saturation: Int, rgb: Int, revision: Int) {
        guard revision == colorRevision, let index = selectedDeviceIndex else {
            return
        }

        pendingColorRGB = nil
        devices[index].state.hue = hue.clamped(to: 0...359)
        devices[index].state.saturation = saturation.clamped(to: 0...100)
        devices[index].state.rgb = rgb.clamped(to: 0...0xFFFFFF)
        devices[index].state.colorMode = .hsv
        devices[index].state.flowing = false
        devices[index].state.flowParameters = ""
        devices[index].state.online = true
        selectedColor = Color(yeelightRGB: rgb)
        lightControlMode = .color
        preferences.savedDevices = devices
        persistDeferred()
    }

    private func commitAppliedPreset(_ preset: LightPreset) {
        guard let index = selectedDeviceIndex else {
            return
        }

        devices[index].state.power = .on
        devices[index].state.online = true

        switch preset.kind {
        case .color:
            devices[index].state.rgb = preset.rgb.clamped(to: 0...0xFFFFFF)
            devices[index].state.brightness = preset.brightness.clamped(to: 1...100)
            devices[index].state.colorMode = .rgb
            devices[index].state.flowing = false
            devices[index].state.flowParameters = ""
        case .colorTemperature:
            devices[index].state.colorTemperature = preset.colorTemperature.clamped(to: 1700...6500)
            devices[index].state.brightness = preset.brightness.clamped(to: 1...100)
            devices[index].state.colorMode = .colorTemperature
            devices[index].state.flowing = false
            devices[index].state.flowParameters = ""
        case .hsv:
            devices[index].state.hue = preset.hue.clamped(to: 0...359)
            devices[index].state.saturation = preset.saturation.clamped(to: 0...100)
            devices[index].state.rgb = Color(yeelightHSV: YeelightHSV(
                hue: Double(devices[index].state.hue),
                saturation: Double(devices[index].state.saturation) / 100,
                value: 1
            )).yeelightRGBValue
            devices[index].state.brightness = preset.brightness.clamped(to: 1...100)
            devices[index].state.colorMode = .hsv
            devices[index].state.flowing = false
            devices[index].state.flowParameters = ""
        case .flow:
            devices[index].state.flowing = true
            devices[index].state.flowParameters = preset.flow?.expression ?? ""
        }

        preferences.savedDevices = devices
        persistDeferred()
        updateControlsFromSelectedDevice()
    }

    private func commitFlowStopped() {
        guard let index = selectedDeviceIndex else {
            return
        }

        devices[index].state.flowing = false
        devices[index].state.flowParameters = ""
        devices[index].state.online = true
        preferences.savedDevices = devices
        persistDeferred()
        updateControlsFromSelectedDevice()
    }

    private func upsertCustomPreset(_ preset: LightPreset) {
        let sanitized = preset.sanitizedCustomCopy

        if let index = customPresets.firstIndex(where: { $0.id == sanitized.id }) {
            customPresets[index] = sanitized
        } else {
            customPresets.append(sanitized)
        }

        customPresets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        preferences.customPresets = customPresets
    }

    private func clearPendingColor(revision: Int) {
        guard revision == colorRevision else {
            return
        }

        pendingColorRGB = nil
        if !isUserColorEditingActive {
            updateControlsFromSelectedDevice()
        }
    }

    private func handleColorPanelClosed() {
        isColorPanelActive = false

        if pendingColorRGB == nil, !isColorEditingActive {
            updateControlsFromSelectedDevice()
        }
    }

    private func cancelColorSelection() {
        colorTask?.cancel()
        colorTask = nil
        pendingColorRGB = nil
        isColorEditingActive = false
        isColorPanelActive = false
        colorPanelCoordinator.close()
    }

    private func cancelPendingDeviceWork() {
        powerTask?.cancel()
        powerTask = nil
        brightnessTask?.cancel()
        brightnessTask = nil
        colorTemperatureTask?.cancel()
        colorTemperatureTask = nil
        presetTask?.cancel()
        presetTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        isRefreshingState = false
        cancelColorSelection()
    }

    private func shouldSendBrightness(_ brightness: Int) -> Bool {
        guard lastSentBrightness != brightness else {
            return false
        }

        lastSentBrightness = brightness
        return true
    }

    private func clearLastSentBrightness(_ brightness: Int) {
        if lastSentBrightness == brightness {
            lastSentBrightness = nil
        }
    }

    private func shouldSendColorTemperature(_ colorTemperature: Int) -> Bool {
        guard lastSentColorTemperature != colorTemperature else {
            return false
        }

        lastSentColorTemperature = colorTemperature
        return true
    }

    private func clearLastSentColorTemperature(_ colorTemperature: Int) {
        if lastSentColorTemperature == colorTemperature {
            lastSentColorTemperature = nil
        }
    }

    private func shouldSendColor(_ signature: ColorCommandSignature) -> Bool {
        guard lastSentColorCommand != signature else {
            return false
        }

        lastSentColorCommand = signature
        return true
    }

    private func clearLastSentColor(_ signature: ColorCommandSignature) {
        if lastSentColorCommand == signature {
            lastSentColorCommand = nil
        }
    }

    private func resetLastSentControlSignatures() {
        lastSentBrightness = nil
        lastSentColorTemperature = nil
        lastSentColorCommand = nil
    }

    private var selectedDeviceIndex: Int? {
        guard let selectedDeviceID else {
            return nil
        }
        return devices.firstIndex { $0.id == selectedDeviceID }
    }

    private func markSelectedDeviceOffline(message: String? = nil) {
        if let index = selectedDeviceIndex {
            devices[index].state.online = false
        }

        isConnectionReady = false

        if let message {
            status = .error(message)
        } else {
            status = .offline
        }

        persistDeferred()
    }

    private func updateControlsFromSelectedDevice() {
        guard let selectedDevice else {
            deviceViewSnapshot = .empty
            isPowerOn = false
            brightness = 50
            colorTemperature = 4000
            selectedColor = Color(yeelightRGB: 0xFFFFFF)
            isColorEditingActive = false
            lightControlMode = .white
            return
        }

        deviceViewSnapshot = DeviceViewSnapshot.make(device: selectedDevice)
        isPowerOn = selectedDevice.state.power == .on
        brightness = Double(selectedDevice.state.brightness)
        colorTemperature = Double(selectedDevice.state.colorTemperature)
        lightControlMode = LightControlMode.inferred(from: selectedDevice.state)

        if let pendingColorRGB {
            selectedColor = Color(yeelightRGB: pendingColorRGB)
        } else if !isUserColorEditingActive {
            if selectedDevice.state.colorMode == .hsv {
                selectedColor = Color(yeelightHSV: YeelightHSV(
                    hue: Double(selectedDevice.state.hue),
                    saturation: Double(selectedDevice.state.saturation) / 100,
                    value: 1
                ))
            } else {
                selectedColor = Color(yeelightRGB: selectedDevice.state.rgb)
            }
        }
    }

    private func rebuildPresetSnapshot() {
        presetSnapshot = PresetSnapshot.make(
            customPresets: customPresets,
            favoritePresetIDs: favoritePresetIDs
        )
    }

    func encodedPreferences() throws -> Data {
        try JSONEncoder.prettyYeelight.encode(currentPreferences())
    }

    func applyImportedPreferences(_ data: Data) throws {
        let imported = try Self.decodeImportedPreferences(data)
        applyImportedPreferences(imported)
    }

    private func applyImportedPreferences(_ imported: AppPreferences) {
        cancelColorSelection()
        disconnectCurrentConnection()
        applyPreferences(imported, reconnect: true)
        persist()
    }

    nonisolated private static func decodeImportedPreferences(_ data: Data) throws -> AppPreferences {
        guard data.count <= 5 * 1024 * 1024 else {
            throw PreferencesImportError.fileTooLarge
        }

        let imported = try JSONDecoder().decode(AppPreferences.self, from: data)
        guard imported.savedDevices.count <= 100 else {
            throw PreferencesImportError.tooManyDevices
        }
        guard imported.customPresets.count <= 500 else {
            throw PreferencesImportError.tooManyPresets
        }
        guard imported.presetShortcuts.count <= 100 else {
            throw PreferencesImportError.tooManyShortcuts
        }
        guard imported.customPresets.allSatisfy({ ($0.flow?.steps.count ?? 0) <= 60 }) else {
            throw PreferencesImportError.flowHasTooManySteps
        }
        return imported
    }

    private func applyPreferences(_ newPreferences: AppPreferences, reconnect: Bool) {
        preferences = sanitizedPreferences(newPreferences)
        devices = preferences.savedDevices
        selectedDeviceID = preferences.selectedDeviceID ?? devices.first?.id
        transitionDuration = preferences.transitionDuration
        discoveryRetryInterval = preferences.discoveryRetryInterval
        reconcileLaunchAtLoginState()
        preferences.launchAtLogin = launchAtLogin
        menuBarIconStyle = preferences.menuBarIconStyle
        defaultManualPort = preferences.defaultManualPort
        commandTimeout = preferences.commandTimeout
        reconnectInterval = preferences.reconnectInterval
        brightnessDebounceMilliseconds = preferences.brightnessDebounceMilliseconds
        colorDebounceMilliseconds = preferences.colorDebounceMilliseconds
        popoverWidth = preferences.popoverWidth
        controlDisplayMode = preferences.controlDisplayMode
        showColorControl = preferences.showColorControl
        debugLoggingEnabled = preferences.debugLoggingEnabled
        customPresets = preferences.customPresets
        favoritePresetIDs = preferences.favoritePresetIDs
        selectedPresetID = preferences.selectedPresetID
        shortcutsEnabled = preferences.shortcutsEnabled
        keyboardShortcuts = preferences.keyboardShortcuts
        presetShortcuts = preferences.presetShortcuts
        shortcutBrightnessStep = preferences.shortcutBrightnessStep
        manualPort = String(defaultManualPort)
        scheduleDiscoveryRetry()
        updateControlsFromSelectedDevice()
        applyHotKeyRegistrations()

        if reconnect, selectedDeviceID != nil {
            connectToSelectedDevice()
        }
    }

    private func currentPreferences() -> AppPreferences {
        AppPreferences(
            savedDevices: devices,
            selectedDeviceID: selectedDeviceID,
            transitionDuration: transitionDuration,
            discoveryRetryInterval: discoveryRetryInterval,
            launchAtLogin: launchAtLogin,
            menuBarIconStyle: menuBarIconStyle,
            defaultManualPort: defaultManualPort,
            commandTimeout: commandTimeout,
            reconnectInterval: reconnectInterval,
            brightnessDebounceMilliseconds: brightnessDebounceMilliseconds,
            colorDebounceMilliseconds: colorDebounceMilliseconds,
            popoverWidth: popoverWidth,
            controlDisplayMode: controlDisplayMode,
            showColorControl: showColorControl,
            debugLoggingEnabled: debugLoggingEnabled,
            customPresets: customPresets,
            favoritePresetIDs: favoritePresetIDs,
            selectedPresetID: selectedPresetID,
            shortcutsEnabled: shortcutsEnabled,
            keyboardShortcuts: keyboardShortcuts,
            presetShortcuts: presetShortcuts,
            shortcutBrightnessStep: shortcutBrightnessStep
        )
    }

    private func sanitizedPreferences(_ preferences: AppPreferences) -> AppPreferences {
        let availableBuiltInIDs = Set(LightPreset.builtIns.map(\.id))
        var seenDeviceIDs = Set<String>()
        let sanitizedDevices = preferences.savedDevices.prefix(100).compactMap { device -> YeelightDevice? in
            let id = sanitizedField(device.id, maximumLength: 128)
            let host = sanitizedField(device.host, maximumLength: 255)
            guard !id.isEmpty,
                  LocalNetworkEndpointPolicy.isAllowedDiscoveryHost(host),
                  seenDeviceIDs.insert(id).inserted else { return nil }
            let capabilities = device.capabilities
                .prefix(64)
                .map { sanitizedField($0, maximumLength: 64) }
                .filter { !$0.isEmpty }
            return YeelightDevice(
                id: id,
                name: sanitizedField(device.name, maximumLength: 128),
                model: sanitizedField(device.model, maximumLength: 128),
                host: host,
                port: device.port,
                capabilities: Set(capabilities),
                state: device.state,
                lastSeen: device.lastSeen
            )
        }

        var seenPresetIDs = availableBuiltInIDs
        let sanitizedCustomPresets = preferences.customPresets.prefix(500).compactMap { preset -> LightPreset? in
            let sanitized = preset.sanitizedCustomCopy
            let id = sanitizedField(sanitized.id, maximumLength: 128)
            let title = sanitizedField(sanitized.title, maximumLength: 128)
            guard !id.isEmpty, !title.isEmpty, seenPresetIDs.insert(id).inserted else { return nil }
            let flow = sanitized.flow.map {
                ColorFlow(count: $0.count, stopAction: $0.stopAction, steps: Array($0.steps.prefix(60)))
            }
            return LightPreset(
                id: id,
                title: title,
                kind: sanitized.kind,
                brightness: sanitized.brightness,
                rgb: sanitized.rgb,
                colorTemperature: sanitized.colorTemperature,
                hue: sanitized.hue,
                saturation: sanitized.saturation,
                flow: flow,
                isBuiltIn: false
            )
        }
        let customIDs = Set(sanitizedCustomPresets.map(\.id))
        let availablePresetIDs = availableBuiltInIDs.union(customIDs)
        var seenFavoriteIDs = Set<String>()
        let favoriteIDs = preferences.favoritePresetIDs.filter {
            availablePresetIDs.contains($0) && seenFavoriteIDs.insert($0).inserted
        }
        let selectedPresetID = availablePresetIDs.contains(preferences.selectedPresetID)
            ? preferences.selectedPresetID
            : LightPreset.reading.id
        let selectedDeviceID = sanitizedDevices.contains { $0.id == preferences.selectedDeviceID }
            ? preferences.selectedDeviceID
            : sanitizedDevices.first?.id

        return AppPreferences(
            savedDevices: sanitizedDevices,
            selectedDeviceID: selectedDeviceID,
            transitionDuration: preferences.transitionDuration.clamped(to: 30...5000),
            discoveryRetryInterval: preferences.discoveryRetryInterval.clamped(to: 5...120),
            launchAtLogin: preferences.launchAtLogin,
            menuBarIconStyle: preferences.menuBarIconStyle,
            defaultManualPort: preferences.defaultManualPort.clamped(to: 1...65535),
            commandTimeout: preferences.commandTimeout.clamped(to: 1...30),
            reconnectInterval: preferences.reconnectInterval.clamped(to: 1...60),
            brightnessDebounceMilliseconds: preferences.brightnessDebounceMilliseconds.clamped(to: 30...1000),
            colorDebounceMilliseconds: preferences.colorDebounceMilliseconds.clamped(to: 30...1000),
            popoverWidth: preferences.popoverWidth.clamped(to: 300...520),
            controlDisplayMode: preferences.controlDisplayMode,
            showColorControl: preferences.showColorControl,
            debugLoggingEnabled: preferences.debugLoggingEnabled,
            customPresets: sanitizedCustomPresets,
            favoritePresetIDs: favoriteIDs,
            selectedPresetID: selectedPresetID,
            shortcutsEnabled: preferences.shortcutsEnabled,
            keyboardShortcuts: sanitizedShortcuts(preferences.keyboardShortcuts),
            presetShortcuts: sanitizedPresetShortcuts(Array(preferences.presetShortcuts.prefix(100))),
            shortcutBrightnessStep: preferences.shortcutBrightnessStep.clamped(to: 1...25)
        )
    }

    private func sanitizedShortcuts(_ shortcuts: [ConfiguredShortcut]) -> [ConfiguredShortcut] {
        var shortcutsByAction: [KeyboardShortcutAction: ConfiguredShortcut] = [:]
        for shortcut in shortcuts {
            shortcutsByAction[shortcut.action] = shortcut
        }

        return KeyboardShortcutAction.allCases.map { action in
            let shortcut = shortcutsByAction[action]
                ?? ConfiguredShortcut(action: action, combination: action.defaultCombination, isEnabled: action.defaultCombination != nil)

            return ConfiguredShortcut(
                action: action,
                combination: shortcut.combination,
                isEnabled: shortcut.isEnabled && shortcut.combination != nil
            )
        }
    }

    private func sanitizedPresetShortcuts(_ shortcuts: [PresetShortcut]) -> [PresetShortcut] {
        var seenIDs = Set<UUID>()
        return shortcuts.compactMap { shortcut in
            guard seenIDs.insert(shortcut.id).inserted else {
                return nil
            }

            let presetID = shortcut.presetID?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PresetShortcut(
                id: shortcut.id,
                presetID: presetID?.isEmpty == true ? nil : presetID,
                combination: shortcut.combination,
                isEnabled: shortcut.isEnabled && shortcut.combination != nil
            )
        }
    }

    private func sanitizedField(_ value: String, maximumLength: Int) -> String {
        let printable = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(printable).prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func debounceNanoseconds(milliseconds: Int) -> UInt64 {
        UInt64(milliseconds.clamped(to: 30...1000)) * 1_000_000
    }

    private func recordDiagnostic(_ message: String, level: DiagnosticLevel = .info) {
        let safeMessage = sanitizedRemoteMessage(message)
        switch level {
        case .debug:
            logger.debug("\(safeMessage, privacy: .private(mask: .hash))")
        case .info:
            logger.info("\(safeMessage, privacy: .private(mask: .hash))")
        case .error:
            logger.error("\(safeMessage, privacy: .private(mask: .hash))")
        }

        guard level != .debug || debugLoggingEnabled else {
            return
        }

        let timestamp = Date().formatted(date: .omitted, time: .standard)
        diagnosticEvents = diagnosticRing.insert("\(timestamp) \(safeMessage)")
    }

    private func sanitizedRemoteMessage(_ message: String) -> String {
        let scalars = message.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar) || scalar.value == 0x20
        }
        return String(String.UnicodeScalarView(scalars).prefix(512))
    }

    private func reconcileLaunchAtLoginState() {
        switch launchAtLoginManager.state {
        case .enabled:
            launchAtLogin = true
            launchAtLoginRequiresApproval = false
        case .requiresApproval:
            launchAtLogin = false
            launchAtLoginRequiresApproval = true
        case .disabled, .unavailable:
            launchAtLogin = false
            launchAtLoginRequiresApproval = false
        }
    }

    private func scheduleDiscoveryRetry() {
        discoveryTimer?.invalidate()
        let interval = Self.effectiveDiscoveryRetryInterval(
            baseInterval: discoveryRetryInterval,
            connected: isConnectionReady
        )
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performDiscovery(isAutomatic: true)
            }
        }
    }

    private func persist() {
        preferences = currentPreferences()
        preferenceSaveScheduler.flush(preferences)
    }

    private func persistDeferred() {
        preferences = currentPreferences()
        preferenceSaveScheduler.schedule(preferences)
    }
}

private extension JSONEncoder {
    static var prettyYeelight: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension Array where Element == YeelightValue {
    var isOKResult: Bool {
        map(\.stringValue) == ["ok"]
    }
}

private extension YeelightIncomingMessage {
    var isOKResult: Bool {
        guard case .result(_, let values) = self else {
            return false
        }

        return values.isOKResult
    }
}
