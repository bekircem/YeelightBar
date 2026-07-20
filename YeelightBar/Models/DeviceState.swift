import Foundation

enum PowerState: String, Codable, Equatable, Sendable {
    case on
    case off
    case unknown
}

enum ColorMode: Int, Codable, Equatable, Sendable {
    case unknown = 0
    case rgb = 1
    case colorTemperature = 2
    case hsv = 3
}

struct DeviceState: Codable, Equatable, Sendable {
    var power: PowerState
    var brightness: Int
    var colorTemperature: Int
    var rgb: Int
    var hue: Int
    var saturation: Int
    var colorMode: ColorMode
    var flowing: Bool
    var flowParameters: String
    var delayOffMinutes: Int
    var online: Bool

    private enum CodingKeys: String, CodingKey {
        case power
        case brightness
        case colorTemperature
        case rgb
        case hue
        case saturation
        case colorMode
        case flowing
        case flowParameters
        case delayOffMinutes
        case online
    }

    static let unknown = DeviceState(
        power: .unknown,
        brightness: 50,
        colorTemperature: 4000,
        rgb: 0xFFFFFF,
        hue: 0,
        saturation: 0,
        colorMode: .unknown,
        flowing: false,
        flowParameters: "",
        delayOffMinutes: 0,
        online: false
    )

    init(
        power: PowerState = .unknown,
        brightness: Int = 50,
        colorTemperature: Int = 4000,
        rgb: Int = 0xFFFFFF,
        hue: Int = 0,
        saturation: Int = 0,
        colorMode: ColorMode = .unknown,
        flowing: Bool = false,
        flowParameters: String = "",
        delayOffMinutes: Int = 0,
        online: Bool = false
    ) {
        self.power = power
        self.brightness = brightness.clamped(to: 1...100)
        self.colorTemperature = colorTemperature.clamped(to: 1700...6500)
        self.rgb = rgb.clamped(to: 0...0xFFFFFF)
        self.hue = hue.clamped(to: 0...359)
        self.saturation = saturation.clamped(to: 0...100)
        self.colorMode = colorMode
        self.flowing = flowing
        self.flowParameters = flowParameters
        self.delayOffMinutes = delayOffMinutes.clamped(to: 0...1440)
        self.online = online
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.unknown

        self.init(
            power: try container.decodeIfPresent(PowerState.self, forKey: .power) ?? defaults.power,
            brightness: try container.decodeIfPresent(Int.self, forKey: .brightness) ?? defaults.brightness,
            colorTemperature: try container.decodeIfPresent(Int.self, forKey: .colorTemperature) ?? defaults.colorTemperature,
            rgb: try container.decodeIfPresent(Int.self, forKey: .rgb) ?? defaults.rgb,
            hue: try container.decodeIfPresent(Int.self, forKey: .hue) ?? defaults.hue,
            saturation: try container.decodeIfPresent(Int.self, forKey: .saturation) ?? defaults.saturation,
            colorMode: try container.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? defaults.colorMode,
            flowing: try container.decodeIfPresent(Bool.self, forKey: .flowing) ?? defaults.flowing,
            flowParameters: try container.decodeIfPresent(String.self, forKey: .flowParameters) ?? defaults.flowParameters,
            delayOffMinutes: try container.decodeIfPresent(Int.self, forKey: .delayOffMinutes) ?? defaults.delayOffMinutes,
            online: try container.decodeIfPresent(Bool.self, forKey: .online) ?? defaults.online
        )
    }

    init(headers: [String: String], online: Bool = true) {
        let power = PowerState(rawValue: headers["power"]?.lowercased() ?? "") ?? .unknown
        let brightness = Int(headers["bright"] ?? "") ?? 50
        let colorTemperature = Int(headers["ct"] ?? "") ?? 4000
        let rgb = Int(headers["rgb"] ?? "") ?? 0xFFFFFF
        let hue = Int(headers["hue"] ?? "") ?? 0
        let saturation = Int(headers["sat"] ?? "") ?? 0
        let colorMode = ColorMode(rawValue: Int(headers["color_mode"] ?? "") ?? 0) ?? .unknown
        let flowing = Self.parseBoolLike(headers["flowing"])
        let flowParameters = headers["flow_params"] ?? ""
        let delayOffMinutes = Int(headers["delayoff"] ?? "") ?? 0

        self.init(
            power: power,
            brightness: brightness,
            colorTemperature: colorTemperature,
            rgb: rgb,
            hue: hue,
            saturation: saturation,
            colorMode: colorMode,
            flowing: flowing,
            flowParameters: flowParameters,
            delayOffMinutes: delayOffMinutes,
            online: online
        )
    }

    mutating func apply(properties: [String: String]) {
        if let value = properties["power"] {
            power = PowerState(rawValue: value.lowercased()) ?? power
        }

        if let value = properties["bright"], let parsed = Int(value) {
            brightness = parsed.clamped(to: 1...100)
        }

        if let value = properties["ct"], let parsed = Int(value) {
            colorTemperature = parsed.clamped(to: 1700...6500)
            colorMode = .colorTemperature
        }

        if let value = properties["rgb"], let parsed = Int(value) {
            rgb = parsed.clamped(to: 0...0xFFFFFF)
            colorMode = .rgb
        }

        if let value = properties["hue"], let parsed = Int(value) {
            hue = parsed.clamped(to: 0...359)
            colorMode = .hsv
        }

        if let value = properties["sat"], let parsed = Int(value) {
            saturation = parsed.clamped(to: 0...100)
            colorMode = .hsv
        }

        if let value = properties["color_mode"], let parsed = Int(value) {
            colorMode = ColorMode(rawValue: parsed) ?? colorMode
        }

        if let value = properties["flowing"] {
            flowing = Self.parseBoolLike(value)
        }

        if let value = properties["flow_params"] {
            flowParameters = value
        }

        if let value = properties["delayoff"] {
            delayOffMinutes = (Int(value) ?? 0).clamped(to: 0...1440)
        }
    }

    private static func parseBoolLike(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "1" || normalized == "on" || normalized == "true"
    }
}
