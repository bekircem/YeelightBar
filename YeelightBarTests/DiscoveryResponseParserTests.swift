import XCTest
@testable import YeelightBar

final class DiscoveryResponseParserTests: XCTestCase {
    func testParsesSearchResponse() throws {
        let message = """
        HTTP/1.1 200 OK\r
        Cache-Control: max-age=3600\r
        Location: yeelight://192.168.1.239:55443\r
        id: 0x000000000015243f\r
        model: color\r
        support: get_prop set_power toggle set_bright set_ct_abx set_rgb\r
        power: on\r
        bright: 75\r
        color_mode: 2\r
        ct: 3500\r
        rgb: 16711680\r
        hue: 100\r
        sat: 35\r
        name: Desk\r
        \r

        """

        let device = try DiscoveryResponseParser.parse(message)

        XCTAssertEqual(device.id, "0x000000000015243f")
        XCTAssertEqual(device.name, "Desk")
        XCTAssertEqual(device.model, "color")
        XCTAssertEqual(device.host, "192.168.1.239")
        XCTAssertEqual(device.port, 55443)
        XCTAssertTrue(device.capabilities.contains("set_rgb"))
        XCTAssertEqual(device.state.power, .on)
        XCTAssertEqual(device.state.brightness, 75)
        XCTAssertEqual(device.state.colorTemperature, 3500)
    }

    func testParsesAdvertisementWithWrappedSupportHeader() throws {
        let message = """
        NOTIFY * HTTP/1.1\r
        Host: 239.255.255.250:1982\r
        Location: yeelight://10.0.0.24:55443\r
        NTS: ssdp:alive\r
        id: 0xabc\r
        model: color\r
        support: get_prop set_power toggle set_bright\r
        set_ct_abx set_rgb\r
        power: off\r
        bright: 10\r
        \r

        """

        let device = try DiscoveryResponseParser.parse(message)

        XCTAssertEqual(device.id, "0xabc")
        XCTAssertEqual(device.host, "10.0.0.24")
        XCTAssertTrue(device.capabilities.contains("set_ct_abx"))
        XCTAssertTrue(device.capabilities.contains("set_rgb"))
        XCTAssertEqual(device.state.power, .off)
    }

    func testRejectsDiscoveryWhenSourceDoesNotMatchLocation() {
        let message = "HTTP/1.1 200 OK\r\nLocation: yeelight://192.168.1.20:55443\r\nid: bulb\r\n\r\n"

        XCTAssertThrowsError(try DiscoveryResponseParser.parse(message, sourceHost: "192.168.1.21")) { error in
            guard case YeelightProtocolError.invalidLocation = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsPublicDiscoveryEndpoint() {
        let message = "HTTP/1.1 200 OK\r\nLocation: yeelight://8.8.8.8:55443\r\nid: bulb\r\n\r\n"

        XCTAssertThrowsError(try DiscoveryResponseParser.parse(message, sourceHost: "8.8.8.8"))
    }

    func testCapsUntrustedDiscoveryStringsAndCapabilities() throws {
        let capabilities = (0..<80).map { "capability-\($0)-" + String(repeating: "x", count: 80) }.joined(separator: " ")
        let message = "HTTP/1.1 200 OK\r\nLocation: yeelight://192.168.1.20:55443\r\nid: \(String(repeating: "i", count: 200))\r\nname: \(String(repeating: "n", count: 200))\r\nmodel: \(String(repeating: "m", count: 200))\r\nsupport: \(capabilities)\r\n\r\n"

        let device = try DiscoveryResponseParser.parse(message, sourceHost: "192.168.1.20")

        XCTAssertEqual(device.id.count, 128)
        XCTAssertEqual(device.name.count, 128)
        XCTAssertEqual(device.model.count, 128)
        XCTAssertEqual(device.capabilities.count, 64)
        XCTAssertTrue(device.capabilities.allSatisfy { $0.count <= 64 })
    }
}

final class DiscoveryCandidateRegistryTests: XCTestCase {
    func testCandidateCapAndDeduplicationUnderFlood() {
        var registry = DiscoveryCandidateRegistry()
        let now = Date(timeIntervalSince1970: 10_000)

        for index in 0..<1_000 {
            let source = "192.168.\((index / 250) + 1).\((index % 250) + 1)"
            guard registry.acceptsPacket(from: source, at: now) else { continue }
            registry.upsert(candidate(id: "device-\(index)", source: source, date: now), at: now)
        }

        XCTAssertEqual(registry.candidates.count, 100)

        let first = registry.candidates[0]
        registry.upsert(candidate(id: first.device.id, source: first.sourceHost, date: now.addingTimeInterval(1)), at: now)
        XCTAssertEqual(registry.candidates.count, 100)
    }

    func testCandidateTTLPrunesExpiredEntries() {
        var registry = DiscoveryCandidateRegistry()
        let initial = Date(timeIntervalSince1970: 1_000)
        let item = candidate(id: "expired", source: "192.168.1.2", date: initial)

        XCTAssertTrue(registry.acceptsPacket(from: item.sourceHost, at: initial))
        registry.upsert(item, at: initial)
        XCTAssertEqual(registry.candidates.count, 1)

        registry.prune(at: initial.addingTimeInterval(121))
        XCTAssertTrue(registry.candidates.isEmpty)
    }

    func testSourceRateAndSourceTableLimits() {
        var registry = DiscoveryCandidateRegistry()
        let now = Date(timeIntervalSince1970: 5_000)

        for _ in 0..<20 {
            XCTAssertTrue(registry.acceptsPacket(from: "192.168.1.2", at: now))
        }
        XCTAssertFalse(registry.acceptsPacket(from: "192.168.1.2", at: now))
        XCTAssertTrue(registry.acceptsPacket(from: "192.168.1.2", at: now.addingTimeInterval(11)))

        var sourceLimitedRegistry = DiscoveryCandidateRegistry()
        for index in 0..<100 {
            XCTAssertTrue(sourceLimitedRegistry.acceptsPacket(from: "fd00::\(index)", at: now))
        }
        XCTAssertFalse(sourceLimitedRegistry.acceptsPacket(from: "fd00::overflow", at: now))
    }

    private func candidate(id: String, source: String, date: Date) -> DiscoveryCandidate {
        DiscoveryCandidate(
            device: YeelightDevice(
                id: id,
                name: id,
                model: "color",
                host: source,
                port: 55443,
                capabilities: [],
                state: .unknown,
                lastSeen: date
            ),
            sourceHost: source,
            discoveredAt: date,
            endpointChanged: false
        )
    }
}
