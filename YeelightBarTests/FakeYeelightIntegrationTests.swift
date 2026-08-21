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

    @MainActor
    func testSleepTimerSchedulesCurrentAppearanceOnSelectedDevice() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .current)

        guard case .success = result else {
            XCTFail("Expected the sleep timer to be scheduled, got \(result)")
            server.stop()
            return
        }
        let sentTimer = await waitFor {
            server.recordedCommands().contains {
                $0.method == "cron_add" && $0.params == ["0", "15"]
            }
        }
        XCTAssertTrue(sentTimer)
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 15)

        server.stop()
    }

    @MainActor
    func testSleepTimerAppliesSoftRoseAfterSchedulingDeviceTimer() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del", "set_scene", "set_rgb"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .softRose)

        XCTAssertEqual(result, .success)
        let commands = server.recordedCommands()
        let timerIndex = try XCTUnwrap(commands.firstIndex { $0.method == "cron_add" })
        let appearanceIndex = try XCTUnwrap(commands.firstIndex { $0.method == "set_scene" })
        XCTAssertLessThan(timerIndex, appearanceIndex)
        XCTAssertEqual(commands[appearanceIndex].params, ["color", "16740241", "5"])
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 15)

        server.stop()
    }

    @MainActor
    func testSleepTimerKeepsTimerWhenAppearanceFails() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .failMethod("set_scene"))
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del", "set_scene", "set_rgb"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 30, appearance: .softRose)

        guard case .timerStartedAppearanceFailed = result else {
            XCTFail("Expected a partial success when the appearance fails, got \(result)")
            server.stop()
            return
        }
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 30)
        XCTAssertTrue(server.recordedCommands().contains { $0.method == "cron_add" })
        XCTAssertTrue(server.recordedCommands().contains { $0.method == "set_scene" })

        server.stop()
    }

    @MainActor
    func testSleepTimerRejectsColorAppearanceWithoutColorCapability() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del", "set_scene"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .softRose)

        guard case .failure = result else {
            XCTFail("Expected an unsupported appearance to fail, got \(result)")
            server.stop()
            return
        }
        XCTAssertFalse(server.recordedCommands().contains { $0.method == "cron_add" })
        XCTAssertTrue(state.compatibleSleepTimerPresets.isEmpty)

        server.stop()
    }

    @MainActor
    func testSleepTimerDoesNotConfirmDifferentReportedDuration() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .failMethod("cron_add"))
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)
        let initialRefreshFinished = await waitFor {
            server.recordedCommands().contains { $0.method == "get_prop" }
        }
        XCTAssertTrue(initialRefreshFinished)
        server.setDelayOffMinutes(5)

        let result = await state.scheduleSleepTimer(minutes: 30, appearance: .current)

        guard case .failure = result else {
            XCTFail("Expected a different reported timer duration to be rejected, got \(result)")
            server.stop()
            return
        }
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 5)

        server.stop()
    }

    @MainActor
    func testSleepTimerReportsWhenReplacementAndRestoreBothFail() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .failMethod("cron_add"))
        server.setDelayOffMinutes(5)
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, delayOffMinutes: 5, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 30, appearance: .current)

        guard case .failure(let message) = result else {
            XCTFail("Expected replacement and restoration failure, got \(result)")
            server.stop()
            return
        }
        XCTAssertTrue(message.contains("previous timer is no longer active"))
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 0)

        server.stop()
    }

    @MainActor
    func testNewSleepTimerRequestSupersedesOlderSameSessionResult() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .delayed(0.35))
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let firstRequest = Task {
            await state.scheduleSleepTimer(minutes: 15, appearance: .current)
        }
        let firstWasSent = await waitFor {
            server.recordedCommands().contains {
                $0.method == "cron_add" && $0.params == ["0", "15"]
            }
        }
        XCTAssertTrue(firstWasSent)

        let secondResult = await state.scheduleSleepTimer(minutes: 30, appearance: .current)
        _ = await firstRequest.value

        XCTAssertEqual(secondResult, .success)
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 30)

        server.stop()
    }

    @MainActor
    func testSleepTimerCancelRemovesDeviceTimer() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)
        let scheduleResult = await state.scheduleSleepTimer(minutes: 30, appearance: .current)
        guard case .success = scheduleResult else {
            XCTFail("Expected the sleep timer to be scheduled before cancellation")
            server.stop()
            return
        }

        let didCancel = await state.cancelSleepTimer()
        XCTAssertTrue(didCancel)
        let sentCancellation = await waitFor {
            server.recordedCommands().contains {
                $0.method == "cron_del" && $0.params == ["0"]
            }
        }
        XCTAssertTrue(sentCancellation)
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 0)

        server.stop()
    }

    @MainActor
    func testSleepTimerDoesNotSendCommandsToUnsupportedDevice() async throws {
        let server = try FakeYeelightTCPServer()
        try await server.start()
        var device = makeDevice(port: server.port, capabilities: ["cron_add", "cron_del"])
        device.state = DeviceState(power: .on, online: true)
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(preferencesData(for: device))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .current)

        guard case .failure = result else {
            XCTFail("Expected unsupported timer scheduling to fail, got \(result)")
            server.stop()
            return
        }
        XCTAssertFalse(server.recordedCommands().contains {
            $0.method == "cron_add" || $0.method == "cron_del"
        })

        server.stop()
    }

    @MainActor
    func testSleepTimerRejectsOfflineStateBeforeSending() async {
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .current)

        guard case .failure = result else {
            XCTFail("Expected offline timer scheduling to fail, got \(result)")
            return
        }
        XCTAssertFalse(state.connectionReady)
        XCTAssertNil(state.selectedDeviceID)
    }

    @MainActor
    func testSleepTimerReturnsVerificationPendingWhenAcceptedCommandCannotBeConfirmed() async throws {
        let server = try FakeYeelightTCPServer(responseMode: .noResponse)
        try await server.start()
        var device = makeDevice(
            port: server.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        device.state = DeviceState(power: .on, online: true)
        let preferences = AppPreferences(
            savedDevices: [device],
            selectedDeviceID: device.id,
            transitionDuration: 30,
            discoveryRetryInterval: 15,
            launchAtLogin: false,
            commandTimeout: 1,
            brightnessDebounceMilliseconds: 30,
            colorDebounceMilliseconds: 30
        )
        let state = AppState(store: makeIsolatedStore(), hotKeyManager: DisabledGlobalHotKeyManager())

        try state.applyImportedPreferences(JSONEncoder().encode(preferences))
        let connected = await waitFor { state.connectionReady }
        XCTAssertTrue(connected)

        let result = await state.scheduleSleepTimer(minutes: 15, appearance: .current)

        guard case .verificationPending = result else {
            XCTFail("Expected an unconfirmed timer result, got \(result)")
            server.stop()
            return
        }
        XCTAssertTrue(server.recordedCommands().contains {
            $0.method == "cron_add" && $0.params == ["0", "15"]
        })

        server.stop()
    }

    @MainActor
    func testSwitchingDevicesDoesNotApplyDelayedSleepTimerResultToNewDevice() async throws {
        let firstServer = try FakeYeelightTCPServer(responseMode: .delayed(0.4))
        let secondServer = try FakeYeelightTCPServer()
        try await firstServer.start()
        try await secondServer.start()

        var firstDevice = makeDevice(
            port: firstServer.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        firstDevice.id = "first-sleep-device"
        firstDevice.state = DeviceState(power: .on, online: true)
        var secondDevice = makeDevice(
            port: secondServer.port,
            capabilities: ["get_prop", "cron_add", "cron_del"]
        )
        secondDevice.id = "second-sleep-device"
        secondDevice.state = DeviceState(power: .on, online: true)

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

        let scheduleTask = Task {
            await state.scheduleSleepTimer(minutes: 15, appearance: .current)
        }
        let sentTimer = await waitFor {
            firstServer.recordedCommands().contains { $0.method == "cron_add" }
        }
        XCTAssertTrue(sentTimer)

        state.selectDevice(id: secondDevice.id)
        let secondConnected = await waitFor {
            state.connectionReady && state.selectedDeviceID == secondDevice.id
        }
        XCTAssertTrue(secondConnected)
        _ = await scheduleTask.value
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(state.selectedDeviceID, secondDevice.id)
        XCTAssertEqual(state.selectedDeviceDelayOffMinutes, 0)
        XCTAssertFalse(secondServer.recordedCommands().contains {
            $0.method == "cron_add" || $0.method == "cron_del"
        })

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
    case failMethod(String)
}

private final class FakeYeelightTCPServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "FakeYeelightTCPServer")
    private let listener: NWListener
    private let responseMode: FakeResponseMode
    private var connection: NWConnection?
    private var commands: [RecordedCommand] = []
    private var delayOffMinutes = 0
    private var receiveBuffer = Data()

    private static let frameDelimiter = Data([0x0D, 0x0A])

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
                self?.receiveBuffer.removeAll(keepingCapacity: true)
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

    func setDelayOffMinutes(_ minutes: Int) {
        queue.sync {
            delayOffMinutes = minutes.clamped(to: 0...60)
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

            if let data, !data.isEmpty {
                self.receiveBuffer.append(data)
                self.processCompleteFrames(on: connection)
            }

            self.receive(on: connection)
        }
    }

    private func processCompleteFrames(on connection: NWConnection) {
        while let delimiterRange = receiveBuffer.range(of: Self.frameDelimiter) {
            let frame = receiveBuffer.subdata(in: receiveBuffer.startIndex..<delimiterRange.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex..<delimiterRange.upperBound)
            processFrame(frame, on: connection)
        }
    }

    private func processFrame(_ frame: Data, on connection: NWConnection) {
        guard !frame.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: frame),
              let dictionary = object as? [String: Any],
              let id = dictionary["id"] as? Int else {
            return
        }

        let method = dictionary["method"] as? String ?? ""
        let params = (dictionary["params"] as? [Any] ?? []).map { String(describing: $0) }
        commands.append(RecordedCommand(method: method, params: params))

        let commandShouldFail: Bool
        if case .failMethod(let failingMethod) = responseMode {
            commandShouldFail = failingMethod == method
        } else {
            commandShouldFail = false
        }

        if !commandShouldFail, method == "cron_add", params.count >= 2 {
            delayOffMinutes = Int(params[1]) ?? 0
        } else if !commandShouldFail, method == "cron_del" {
            delayOffMinutes = 0
        }

        let result: [String]
        if method == "get_prop" {
            result = [
                "on", "50", "4000", "16777215", "0", "0", "1", "0", "",
                String(delayOffMinutes)
            ]
        } else {
            result = ["ok"]
        }

        guard responseMode != .noResponse else {
            return
        }

        if responseMode == .gracefulEOF {
            connection.send(
                content: nil,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { _ in }
            )
            return
        }

        let payload: [String: Any]
        if commandShouldFail {
            payload = [
                "id": id,
                "error": ["code": -1, "message": "Simulated command failure"]
            ]
        } else {
            payload = ["id": id, "result": result]
        }
        guard var responseData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }

        responseData.append(Self.frameDelimiter)
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
        case .failMethod:
            sendResponse()
        case .noResponse:
            break
        }
    }
}
