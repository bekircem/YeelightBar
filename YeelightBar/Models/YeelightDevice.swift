import Foundation

struct YeelightDevice: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var model: String
    var host: String
    var port: UInt16
    var capabilities: Set<String>
    var state: DeviceState
    var lastSeen: Date

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }

        if !model.isEmpty {
            return "\(model.capitalized) \(id.suffix(6))"
        }

        return "Yeelight \(id.suffix(6))"
    }

    func supports(_ method: YeelightMethod) -> Bool {
        capabilities.contains(method.rawValue)
    }
}
