import Foundation

enum YeelightMethod: String, Codable, CaseIterable, Sendable {
    case getProp = "get_prop"
    case setPower = "set_power"
    case toggle
    case setBrightness = "set_bright"
    case setColorTemperature = "set_ct_abx"
    case setRGB = "set_rgb"
    case setHSV = "set_hsv"
    case startColorFlow = "start_cf"
    case stopColorFlow = "stop_cf"
    case setScene = "set_scene"
}

enum YeelightParameter: Equatable, Sendable {
    case string(String)
    case int(Int)

    var jsonValue: Any {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return value
        }
    }
}

struct YeelightCommand: Equatable, Sendable {
    var id: Int
    var method: YeelightMethod
    var params: [YeelightParameter]

    func jsonData() throws -> Data {
        let payload: [String: Any] = [
            "id": id,
            "method": method.rawValue,
            "params": params.map(\.jsonValue)
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    func framedData() throws -> Data {
        var data = try jsonData()
        data.append(contentsOf: [0x0D, 0x0A])
        return data
    }

    static func getProperties(id: Int, _ properties: [String]) -> YeelightCommand {
        YeelightCommand(id: id, method: .getProp, params: properties.map { .string($0) })
    }

    static func setPower(id: Int, isOn: Bool, effect: String = "smooth", duration: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setPower,
            params: [.string(isOn ? "on" : "off"), .string(effect), .int(duration)]
        )
    }

    static func setBrightness(id: Int, brightness: Int, effect: String = "smooth", duration: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setBrightness,
            params: [.int(brightness.clamped(to: 1...100)), .string(effect), .int(duration)]
        )
    }

    static func setColorTemperature(id: Int, temperature: Int, effect: String = "smooth", duration: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setColorTemperature,
            params: [.int(temperature.clamped(to: 1700...6500)), .string(effect), .int(duration)]
        )
    }

    static func setRGB(id: Int, rgb: Int, effect: String = "smooth", duration: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setRGB,
            params: [.int(rgb.clamped(to: 0...0xFFFFFF)), .string(effect), .int(duration)]
        )
    }

    static func setHSV(id: Int, hue: Int, saturation: Int, effect: String = "smooth", duration: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setHSV,
            params: [.int(hue.clamped(to: 0...359)), .int(saturation.clamped(to: 0...100)), .string(effect), .int(duration)]
        )
    }

    static func setSceneColor(id: Int, rgb: Int, brightness: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setScene,
            params: [.string("color"), .int(rgb.clamped(to: 0...0xFFFFFF)), .int(brightness.clamped(to: 1...100))]
        )
    }

    static func setSceneHSV(id: Int, hue: Int, saturation: Int, brightness: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setScene,
            params: [
                .string("hsv"),
                .int(hue.clamped(to: 0...359)),
                .int(saturation.clamped(to: 0...100)),
                .int(brightness.clamped(to: 1...100))
            ]
        )
    }

    static func setSceneColorTemperature(id: Int, temperature: Int, brightness: Int) -> YeelightCommand {
        YeelightCommand(
            id: id,
            method: .setScene,
            params: [
                .string("ct"),
                .int(temperature.clamped(to: 1700...6500)),
                .int(brightness.clamped(to: 1...100))
            ]
        )
    }

    static func startColorFlow(id: Int, flow: ColorFlow) -> YeelightCommand {
        let sanitized = flow.sanitized
        return YeelightCommand(
            id: id,
            method: .startColorFlow,
            params: [.int(sanitized.count), .int(sanitized.stopAction.rawValue), .string(sanitized.expression)]
        )
    }

    static func stopColorFlow(id: Int) -> YeelightCommand {
        YeelightCommand(id: id, method: .stopColorFlow, params: [])
    }

    static func setSceneColorFlow(id: Int, flow: ColorFlow) -> YeelightCommand {
        let sanitized = flow.sanitized
        return YeelightCommand(
            id: id,
            method: .setScene,
            params: [.string("cf"), .int(sanitized.count), .int(sanitized.stopAction.rawValue), .string(sanitized.expression)]
        )
    }
}
