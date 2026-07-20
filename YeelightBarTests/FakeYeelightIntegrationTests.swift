import Network
import XCTest
@testable import YeelightBar

final class FakeYeelightIntegrationTests: XCTestCase {
    func testConnectionSendsCommandAndReceivesResult() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()

        let device = YeelightDevice(
            id: "fake",
            name: "Fake",
            model: "color",
            host: "127.0.0.1",
            port: server.port,
            capabilities: ["get_prop", "set_power"],
            state: .unknown,
            lastSeen: Date()
        )

        let connection = YeelightConnection()
        await connection.connect(to: device)

        try await Task.sleep(nanoseconds: 200_000_000)
        let result = try await connection.send(.setPower(id: 1, isOn: true, duration: 30))

        XCTAssertEqual(result, .result(id: 1, values: [.string("ok")]))

        await connection.disconnect()
        server.stop()
    }

    func testConnectionTimesOutUnansweredCommandAndCleansPending() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .noResponse)
        try await server.start()
        let device = makeDevice(port: server.port, capabilities: ["set_power"])
        let connection = YeelightConnection()
        await connection.connect(to: device)

        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await connection.send(.setPower(id: 1, isOn: true, duration: 30), timeout: 0.05)
            XCTFail("Expected command timeout")
        } catch let error as YeelightProtocolError {
            XCTAssertEqual(error, .timedOut)
        }

        let pendingCount = await connection.pendingCommandCount()
        XCTAssertEqual(pendingCount, 0)

        await connection.disconnect()
        server.stop()
    }

    func testDisconnectFailsPendingCommandAndCleansPending() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .noResponse)
        try await server.start()
        let device = makeDevice(port: server.port, capabilities: ["set_power"])
        let connection = YeelightConnection()
        await connection.connect(to: device)

        try await Task.sleep(nanoseconds: 100_000_000)

        let sendTask = Task {
            try await connection.send(.setPower(id: 1, isOn: true, duration: 30), timeout: 5)
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await connection.disconnect()

        do {
            _ = try await sendTask.value
            XCTFail("Expected pending command to fail on disconnect")
        } catch let error as YeelightProtocolError {
            XCTAssertEqual(error, .disconnected)
        }

        let pendingCount = await connection.pendingCommandCount()
        XCTAssertEqual(pendingCount, 0)

        server.stop()
    }

    func testConnectionAcceptsFragmentedResponse() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .fragmented)
        try await server.start()
        let connection = YeelightConnection()
        await connection.connect(to: makeDevice(port: server.port, capabilities: ["set_power"]))
        try await Task.sleep(nanoseconds: 100_000_000)

        let result = try await connection.send(.setPower(id: 17, isOn: true, duration: 30))

        XCTAssertEqual(result, .result(id: 17, values: [.string("ok")]))
        await connection.disconnect()
        server.stop()
    }

    func testConnectionAcceptsCombinedFrames() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .combinedFrames)
        try await server.start()
        let connection = YeelightConnection()
        await connection.connect(to: makeDevice(port: server.port, capabilities: ["set_power"]))
        try await Task.sleep(nanoseconds: 100_000_000)

        let result = try await connection.send(.setPower(id: 21, isOn: true, duration: 30))

        XCTAssertEqual(result, .result(id: 21, values: [.string("ok")]))
        await connection.disconnect()
        server.stop()
    }

    func testGracefulEOFFailsPendingCommandAndCleansPending() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .gracefulEOF)
        try await server.start()
        let connection = YeelightConnection()
        await connection.connect(to: makeDevice(port: server.port, capabilities: ["set_power"]))
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await connection.send(.setPower(id: 22, isOn: true, duration: 30))
            XCTFail("Expected graceful EOF to fail the command")
        } catch let error as YeelightProtocolError {
            XCTAssertEqual(error, .disconnected)
        }

        let pendingCount = await connection.pendingCommandCount()
        XCTAssertEqual(pendingCount, 0)
        server.stop()
    }

    func testOversizedLogicalFrameClosesConnectionAndFailsPendingCommand() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .oversizedFrame)
        try await server.start()
        let connection = YeelightConnection()
        await connection.connect(to: makeDevice(port: server.port, capabilities: ["set_power"]))
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await connection.send(.setPower(id: 18, isOn: true, duration: 30))
            XCTFail("Expected oversized frame rejection")
        } catch let error as YeelightProtocolError {
            XCTAssertEqual(error, .logicalFrameTooLarge(limit: YeelightConnection.maximumLogicalFrameSize))
        }

        let pendingCount = await connection.pendingCommandCount()
        XCTAssertEqual(pendingCount, 0)
        server.stop()
    }

    func testMalformedFrameFailsPendingCommand() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .malformedFrame)
        try await server.start()
        let connection = YeelightConnection()
        await connection.connect(to: makeDevice(port: server.port, capabilities: ["set_power"]))
        try await Task.sleep(nanoseconds: 100_000_000)

        do {
            _ = try await connection.send(.setPower(id: 19, isOn: true, duration: 30))
            XCTFail("Expected malformed frame rejection")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        let pendingCount = await connection.pendingCommandCount()
        XCTAssertEqual(pendingCount, 0)
        server.stop()
    }

    @MainActor
    func testAppStateColorWheelUsesHSVWhenSupported() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        let device = makeDevice(port: server.port, capabilities: ["get_prop", "set_hsv", "set_rgb"])
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let didConnect = await waitFor { state.connectionReady }
        XCTAssertTrue(didConnect)

        state.setHueSaturation(hue: 203, saturation: 0.8)

        let didSendHSV = await waitFor {
            server.recordedCommands().contains { $0.method == "set_hsv" }
        }
        XCTAssertTrue(didSendHSV)

        let command = try XCTUnwrap(server.recordedCommands().first { $0.method == "set_hsv" })
        XCTAssertEqual(Array(command.params.prefix(2)), ["203", "80"])

        server.stop()
    }

    @MainActor
    func testAppStateColorWheelFallsBackToRGBWhenHSVIsUnsupported() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        let device = makeDevice(port: server.port, capabilities: ["get_prop", "set_rgb"])
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let didConnect = await waitFor { state.connectionReady }
        XCTAssertTrue(didConnect)

        state.setHueSaturation(hue: 180, saturation: 1)

        let didSendRGB = await waitFor {
            server.recordedCommands().contains { $0.method == "set_rgb" }
        }
        XCTAssertTrue(didSendRGB)
        XCTAssertFalse(server.recordedCommands().contains { $0.method == "set_hsv" })

        let command = try XCTUnwrap(server.recordedCommands().first { $0.method == "set_rgb" })
        XCTAssertEqual(command.params.first, "65535")

        server.stop()
    }

    @MainActor
    func testRapidBrightnessChangesSendOnlyLatestValue() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        let device = makeDevice(port: server.port, capabilities: ["get_prop", "set_bright"])
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let didConnect = await waitFor { state.connectionReady }
        XCTAssertTrue(didConnect)

        for value in 10...19 {
            state.setBrightness(Double(value))
        }

        let didSendBrightness = await waitFor {
            server.recordedCommands().contains { $0.method == "set_bright" }
        }
        XCTAssertTrue(didSendBrightness)

        let brightnessCommands = server.recordedCommands().filter { $0.method == "set_bright" }
        XCTAssertEqual(brightnessCommands.count, 1)
        XCTAssertEqual(brightnessCommands.first?.params.first, "19")

        server.stop()
    }

    @MainActor
    func testSwitchingDevicesRejectsDelayedResultFromOldSession() async throws {
        let firstServer = try FakeYeelightTCPServer(responseMode: .delayed(0.4))
        let secondServer = try FakeYeelightTCPServer()
        try await firstServer.start()
        try await secondServer.start()

        var firstDevice = makeDevice(port: firstServer.port, capabilities: ["get_prop", "set_bright"])
        firstDevice.id = "first-device"
        firstDevice.state.brightness = 40
        var secondDevice = makeDevice(port: secondServer.port, capabilities: ["get_prop", "set_bright"])
        secondDevice.id = "second-device"
        secondDevice.state.brightness = 70

        let preferences = AppPreferences(
            savedDevices: [firstDevice, secondDevice],
            selectedDeviceID: firstDevice.id,
            transitionDuration: 30,
            discoveryRetryInterval: 15,
            launchAtLogin: false,
            brightnessDebounceMilliseconds: 30,
            colorDebounceMilliseconds: 30
        )
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())
        try state.applyImportedPreferences(JSONEncoder().encode(preferences))
        let firstConnected = await waitFor { state.connectionReady }
        XCTAssertTrue(firstConnected)

        state.setBrightness(20)
        let commandWasSent = await waitFor { firstServer.recordedCommands().contains { $0.method == "set_bright" } }
        XCTAssertTrue(commandWasSent)

        state.selectDevice(id: secondDevice.id)
        let secondConnected = await waitFor { state.connectionReady && state.selectedDeviceID == secondDevice.id }
        XCTAssertTrue(secondConnected)
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(state.selectedDeviceID, secondDevice.id)
        XCTAssertNotEqual(state.selectedDevice?.state.brightness, 20)
        firstServer.stop()
        secondServer.stop()
    }

    private func makeDevice(port: UInt16, capabilities: Set<String>) -> YeelightDevice {
        YeelightDevice(
            id: "fake-app-state",
            name: "Fake App State",
            model: "color",
            host: "127.0.0.1",
            port: port,
            capabilities: capabilities,
            state: .unknown,
            lastSeen: Date()
        )
    }

    private func preferencesData(for device: YeelightDevice) throws -> Data {
        let preferences = AppPreferences(
            savedDevices: [device],
            selectedDeviceID: device.id,
            transitionDuration: 30,
            discoveryRetryInterval: 15,
            launchAtLogin: false,
            brightnessDebounceMilliseconds: 30,
            colorDebounceMilliseconds: 30
        )

        return try JSONEncoder().encode(preferences)
    }

    private func makeIsolatedStore() -> DeviceStore {
        let suiteName = "YeelightBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DeviceStore(defaults: defaults)
    }

    @MainActor
    private func waitFor(timeout: TimeInterval = 2, condition: @escaping @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return condition()
    }
}

private struct RecordedCommand: Equatable, Sendable {
    var method: String
    var params: [String]
}

private enum FakeResponseMode: Equatable {
    case normal
    case noResponse
    case delayed(TimeInterval)
    case fragmented
    case combinedFrames
    case gracefulEOF
    case oversizedFrame
    case malformedFrame
}

private final class FakeYeelightTCPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeYeelightTCPServer")
    private let listener: NWListener
    private let responseMode: FakeResponseMode
    private var connection: NWConnection?
    private var commands: [RecordedCommand] = []

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    init(responseMode: FakeResponseMode = .normal) throws {
        self.responseMode = responseMode
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            listener.newConnectionHandler = { [weak self] connection in
                self?.connection = connection
                self?.receive(on: connection)
                connection.start(queue: self?.queue ?? .global())
            }

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    func stop() {
        connection?.cancel()
        listener.cancel()
    }

    func recordedCommands() -> [RecordedCommand] {
        queue.sync {
            commands
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else {
                return
            }

            guard error == nil, !isComplete else {
                return
            }

            if let data, !data.isEmpty,
               let object = try? JSONSerialization.jsonObject(with: data.filter { $0 != 13 && $0 != 10 }),
               let dictionary = object as? [String: Any],
               let id = dictionary["id"] as? Int {
                let method = dictionary["method"] as? String ?? ""
                let params = (dictionary["params"] as? [Any] ?? []).map { String(describing: $0) }
                self.commands.append(RecordedCommand(method: method, params: params))

                let result: [String]
                if method == "get_prop" {
                    result = ["on", "50", "4000", "16777215", "0", "0", "1", "0", "", "0"]
                } else {
                    result = ["ok"]
                }

                if responseMode != .noResponse {
                    if responseMode == .gracefulEOF {
                        connection.send(
                            content: nil,
                            contentContext: .finalMessage,
                            isComplete: true,
                            completion: .contentProcessed { _ in }
                        )
                        return
                    }

                    let payload: [String: Any] = ["id": id, "result": result]
                    if var responseData = try? JSONSerialization.data(withJSONObject: payload, options: []) {
                        responseData.append(contentsOf: [0x0D, 0x0A])
                        let finalResponseData = responseData
                        let sendResponse: @Sendable () -> Void = {
                            connection.send(content: finalResponseData, completion: .contentProcessed { _ in })
                        }

                        switch responseMode {
                        case .normal:
                            sendResponse()
                        case .delayed(let delay):
                            queue.asyncAfter(deadline: .now() + delay, execute: sendResponse)
                        case .fragmented:
                            let splitIndex = finalResponseData.count / 2
                            let first = finalResponseData.prefix(splitIndex)
                            let second = finalResponseData.suffix(from: splitIndex)
                            connection.send(content: Data(first), completion: .contentProcessed { _ in
                                connection.send(content: Data(second), completion: .contentProcessed { _ in })
                            })
                        case .combinedFrames:
                            var combinedData = finalResponseData
                            combinedData.append(finalResponseData)
                            connection.send(content: combinedData, completion: .contentProcessed { _ in })
                        case .gracefulEOF:
                            break
                        case .oversizedFrame:
                            connection.send(
                                content: Data(repeating: 0x41, count: YeelightConnection.maximumLogicalFrameSize + 1),
                                completion: .contentProcessed { _ in }
                            )
                        case .malformedFrame:
                            connection.send(content: Data("{not-json}\r\n".utf8), completion: .contentProcessed { _ in })
                        case .noResponse:
                            break
                        }
                    }
                }
            }

            self.receive(on: connection)
        }
    }
}
