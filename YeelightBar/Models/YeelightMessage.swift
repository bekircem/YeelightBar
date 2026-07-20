import Foundation

struct YeelightErrorMessage: Error, Equatable, Sendable {
    var code: Int
    var message: String
}

enum YeelightValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return ""
        }
    }
}

enum YeelightIncomingMessage: Equatable, Sendable {
    case result(id: Int, values: [YeelightValue])
    case failure(id: Int?, error: YeelightErrorMessage)
    case notification(properties: [String: String])
}

enum YeelightMessageDecoder {
    static func decode(lineData: Data) throws -> YeelightIncomingMessage {
        let object = try JSONSerialization.jsonObject(with: lineData, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw YeelightProtocolError.invalidMessage("Expected JSON object")
        }

        if let method = dictionary["method"] as? String, method == "props" {
            let params = dictionary["params"] as? [String: Any] ?? [:]
            return .notification(properties: params.mapValues { String(describing: $0) })
        }

        let id = dictionary["id"] as? Int

        if let error = dictionary["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown Yeelight error"
            return .failure(id: id, error: YeelightErrorMessage(code: code, message: message))
        }

        guard let id else {
            throw YeelightProtocolError.invalidMessage("Missing response id")
        }

        let rawValues = dictionary["result"] as? [Any] ?? []
        return .result(id: id, values: rawValues.map(decodeValue))
    }

    private static func decodeValue(_ value: Any) -> YeelightValue {
        switch value {
        case let value as String:
            return .string(value)
        case _ as NSNull:
            return .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }

            let doubleValue = value.doubleValue
            if doubleValue.rounded(.towardZero) == doubleValue,
               doubleValue >= Double(Int.min),
               doubleValue <= Double(Int.max) {
                return .int(value.intValue)
            }
            return .double(doubleValue)
        default:
            return .string(String(describing: value))
        }
    }
}
