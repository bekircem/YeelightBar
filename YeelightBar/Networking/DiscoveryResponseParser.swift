import Foundation
import Network

enum YeelightProtocolError: Error, Equatable, Sendable {
    case invalidMessage(String)
    case invalidLocation(String)
    case unsupportedMethod(String)
    case connectionNotReady
    case disconnected
    case timedOut
    case logicalFrameTooLarge(limit: Int)
}

extension YeelightProtocolError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidMessage:
            return "The bulb sent an invalid message."
        case .invalidLocation:
            return "The discovery response contained an invalid endpoint."
        case .unsupportedMethod:
            return "The bulb does not support this command."
        case .connectionNotReady:
            return "The bulb connection is not ready."
        case .disconnected:
            return "The bulb disconnected."
        case .timedOut:
            return "The bulb did not respond in time."
        case .logicalFrameTooLarge(let limit):
            return "The bulb sent a message larger than \(limit) bytes."
        }
    }
}

enum DiscoveryResponseParser {
    static func parse(
        _ message: String,
        sourceHost: String? = nil,
        now: Date = Date()
    ) throws -> YeelightDevice {
        let normalized = message.replacingOccurrences(of: "\r\n", with: "\n")
        let rawLines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") }

        guard let startLine = rawLines.first else {
            throw YeelightProtocolError.invalidMessage("Empty discovery response")
        }

        guard startLine == "HTTP/1.1 200 OK" || startLine == "NOTIFY * HTTP/1.1" else {
            throw YeelightProtocolError.invalidMessage("Unsupported discovery start line: \(startLine)")
        }

        var headers: [String: String] = [:]
        var lastKey: String?

        for line in rawLines.dropFirst() {
            if let separator = line.firstIndex(of: ":") {
                let key = String(line[..<separator]).lowercased()
                let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
                lastKey = key
            } else if let lastKey {
                headers[lastKey, default: ""] += " \(line)"
            }
        }

        guard let rawID = headers["id"], !rawID.isEmpty else {
            throw YeelightProtocolError.invalidMessage("Missing Yeelight device id")
        }

        guard let location = headers["location"] else {
            throw YeelightProtocolError.invalidMessage("Missing Yeelight location")
        }

        let endpoint = try parseLocation(location)
        if let sourceHost {
            guard LocalNetworkEndpointPolicy.hostsMatch(sourceHost, endpoint.host) else {
                throw YeelightProtocolError.invalidLocation("Discovery source does not match Location host")
            }
        }

        guard LocalNetworkEndpointPolicy.isAllowedDiscoveryHost(endpoint.host) else {
            throw YeelightProtocolError.invalidLocation("Discovery endpoint is outside the local network")
        }

        let capabilities = (headers["support"] ?? "")
            .split(whereSeparator: \.isWhitespace)
            .prefix(64)
            .map { sanitizedField(String($0), maximumLength: 64) }
            .filter { !$0.isEmpty }

        return YeelightDevice(
            id: sanitizedField(rawID, maximumLength: 128),
            name: sanitizedField(headers["name"] ?? "", maximumLength: 128),
            model: sanitizedField(headers["model"] ?? "", maximumLength: 128),
            host: endpoint.host,
            port: endpoint.port,
            capabilities: Set(capabilities),
            state: DeviceState(headers: headers, online: true),
            lastSeen: now
        )
    }

    private static func parseLocation(_ location: String) throws -> (host: String, port: UInt16) {
        guard let components = URLComponents(string: location), components.scheme == "yeelight" else {
            throw YeelightProtocolError.invalidLocation(location)
        }

        guard let host = components.host, let port = components.port, let endpointPort = UInt16(exactly: port) else {
            throw YeelightProtocolError.invalidLocation(location)
        }

        return (host, endpointPort)
    }

    private static func sanitizedField(_ value: String, maximumLength: Int) -> String {
        let printable = value.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(printable).prefix(maximumLength))
    }
}

struct DiscoveryCandidate: Identifiable, Equatable, Sendable {
    var device: YeelightDevice
    var sourceHost: String
    var discoveredAt: Date
    var endpointChanged: Bool

    var id: String {
        "\(device.id)|\(sourceHost)"
    }
}

struct DiscoveryCandidateRegistry {
    private(set) var candidates: [DiscoveryCandidate] = []

    private let maximumCandidates: Int
    private let candidateTTL: TimeInterval
    private let maximumSources: Int
    private let sourceWindow: TimeInterval
    private let maximumPacketsPerSource: Int
    private var hitsBySource: [String: [Date]] = [:]

    init(
        maximumCandidates: Int = 100,
        candidateTTL: TimeInterval = 120,
        maximumSources: Int = 100,
        sourceWindow: TimeInterval = 10,
        maximumPacketsPerSource: Int = 20
    ) {
        self.maximumCandidates = maximumCandidates
        self.candidateTTL = candidateTTL
        self.maximumSources = maximumSources
        self.sourceWindow = sourceWindow
        self.maximumPacketsPerSource = maximumPacketsPerSource
    }

    mutating func acceptsPacket(from sourceHost: String, at now: Date = Date()) -> Bool {
        prune(at: now)

        guard hitsBySource[sourceHost] != nil || hitsBySource.count < maximumSources else {
            return false
        }

        let cutoff = now.addingTimeInterval(-sourceWindow)
        var recentHits = hitsBySource[sourceHost, default: []].filter { $0 >= cutoff }
        guard recentHits.count < maximumPacketsPerSource else {
            return false
        }

        recentHits.append(now)
        hitsBySource[sourceHost] = recentHits
        return true
    }

    mutating func upsert(_ candidate: DiscoveryCandidate, at now: Date = Date()) {
        prune(at: now)

        if let index = candidates.firstIndex(where: { $0.id == candidate.id }) {
            candidates[index] = candidate
        } else if candidates.count < maximumCandidates {
            candidates.append(candidate)
        }

        candidates.sort {
            $0.device.displayName.localizedCaseInsensitiveCompare($1.device.displayName) == .orderedAscending
        }
    }

    mutating func remove(candidateID: String) {
        candidates.removeAll { $0.id == candidateID }
    }

    mutating func remove(deviceID: String) {
        candidates.removeAll { $0.device.id == deviceID }
    }

    mutating func prune(at now: Date = Date()) {
        let candidateCutoff = now.addingTimeInterval(-candidateTTL)
        candidates.removeAll { $0.discoveredAt < candidateCutoff }

        let rateCutoff = now.addingTimeInterval(-sourceWindow)
        hitsBySource = hitsBySource.reduce(into: [:]) { result, entry in
            let recentHits = entry.value.filter { $0 >= rateCutoff }
            if !recentHits.isEmpty {
                result[entry.key] = recentHits
            }
        }
    }
}

enum LocalNetworkEndpointPolicy {
    static func hostsMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedHost(lhs) == normalizedHost(rhs)
    }

    static func isAllowedDiscoveryHost(_ host: String) -> Bool {
        let normalized = normalizedHost(host)

        if let address = IPv4Address(normalized) {
            let bytes = Array(address.rawValue)
            guard bytes.count == 4 else { return false }
            let isPrivate = bytes[0] == 10
                || (bytes[0] == 172 && (16...31).contains(bytes[1]))
                || (bytes[0] == 192 && bytes[1] == 168)
            let isLinkLocal = bytes[0] == 169 && bytes[1] == 254
            let isLoopback = bytes[0] == 127
            return isPrivate || isLinkLocal || (allowsLoopback && isLoopback)
        }

        if let address = IPv6Address(normalized) {
            let bytes = Array(address.rawValue)
            guard bytes.count == 16 else { return false }
            let isULA = bytes[0] & 0xFE == 0xFC
            let isLinkLocal = bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
            let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            return isULA || isLinkLocal || (allowsLoopback && isLoopback)
        }

        return false
    }

    private static var allowsLoopback: Bool {
#if DEBUG
        true
#else
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
#endif
    }

    private static func normalizedHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if let zone = value.firstIndex(of: "%") {
            value = String(value[..<zone])
        }
        return value
    }
}
