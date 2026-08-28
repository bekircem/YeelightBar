import AppKit
import SwiftUI
import XCTest
@testable import YeelightBar

@MainActor
final class MenuBarPresentationTests: XCTestCase {
    func testDeviceCardSnapshotsExposeExactlyOneSelectedDevice() {
        let devices = [
            makeDevice(id: "desk", name: "Desk", state: DeviceState(power: .on, brightness: 72, online: true)),
            makeDevice(id: "floor", name: "Floor", state: DeviceState(power: .off, brightness: 35, online: true)),
            makeDevice(id: "hall", name: "Hall", state: .unknown),
            makeDevice(id: "shelf", name: "Shelf", state: DeviceState(power: .on, brightness: 44, online: false))
        ]

        let snapshots = devices.map { DeviceCardSnapshot(device: $0, selectedDeviceID: "floor") }

        XCTAssertEqual(snapshots.filter(\.isSelected).map(\.id), ["floor"])
        XCTAssertEqual(snapshots[0].statusTitle, "On · 72%")
        XCTAssertEqual(snapshots[1].statusTitle, "Off")
        XCTAssertEqual(snapshots[2].statusTitle, "Status unknown")
        XCTAssertEqual(snapshots[3].statusTitle, "Offline · last on at 44%")
    }

    func testDeviceCardUnknownPowerUsesOnlineSummary() {
        let device = makeDevice(
            state: DeviceState(power: .unknown, colorMode: .unknown, online: true)
        )

        let snapshot = DeviceCardSnapshot(device: device, selectedDeviceID: nil)

        XCTAssertEqual(snapshot.statusTitle, "Online")
    }

    func testAmbientColorResolverHandlesRGBHSVTemperatureAndFallback() {
        assertColor(
            DeviceCardSnapshot(
                device: makeDevice(state: DeviceState(rgb: 0x3366CC, colorMode: .rgb, online: true)),
                selectedDeviceID: nil
            ).ambientColor,
            red: 0.2,
            green: 0.4,
            blue: 0.8
        )
        assertColor(
            DeviceCardSnapshot(
                device: makeDevice(state: DeviceState(hue: 180, saturation: 50, colorMode: .hsv, online: true)),
                selectedDeviceID: nil
            ).ambientColor,
            red: 0.5,
            green: 1,
            blue: 1
        )

        assertColor(
            LightAppearanceColorResolver.temperatureColor(kelvin: 1700),
            red: 1,
            green: 0.49,
            blue: 0.16
        )
        assertColor(
            LightAppearanceColorResolver.temperatureColor(kelvin: 6500),
            red: 0.64,
            green: 0.80,
            blue: 1
        )

        let fallback = DeviceCardSnapshot(device: makeDevice(state: .unknown), selectedDeviceID: nil).ambientColor
        assertColor(fallback, red: 1, green: 154.0 / 255.0, blue: 46.0 / 255.0)
    }

    func testQuickScenePresentationLimitsCompactFavorites() {
        let presets = Array(LightPreset.builtIns.prefix(5))

        XCTAssertEqual(
            QuickScenePresentation.visiblePresets(from: presets, displayMode: .detailed),
            presets
        )
        XCTAssertEqual(
            QuickScenePresentation.visiblePresets(from: presets, displayMode: .compact),
            Array(presets.prefix(3))
        )
    }

    private func makeDevice(
        id: String = "test-device",
        name: String = "Desk Lamp",
        state: DeviceState
    ) -> YeelightDevice {
        YeelightDevice(
            id: id,
            name: name,
            model: "color",
            host: "192.168.1.42",
            port: 55443,
            capabilities: ["set_scene", "start_cf"],
            state: state,
            lastSeen: Date(timeIntervalSince1970: 0)
        )
    }

    private func assertColor(
        _ color: Color,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        accuracy: CGFloat = 0.01,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let converted = NSColor(color).usingColorSpace(.deviceRGB) else {
            XCTFail("Color could not be converted to device RGB", file: file, line: line)
            return
        }

        XCTAssertEqual(converted.redComponent, red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(converted.greenComponent, green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(converted.blueComponent, blue, accuracy: accuracy, file: file, line: line)
    }
}
