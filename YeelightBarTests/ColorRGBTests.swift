import SwiftUI
import XCTest
@testable import YeelightBar

final class ColorRGBTests: XCTestCase {
    func testCreatesRGBIntegerFromColor() {
        XCTAssertEqual(Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).yeelightRGBValue, 0xFF0000)
        XCTAssertEqual(Color(.sRGB, red: 0, green: 1, blue: 0, opacity: 1).yeelightRGBValue, 0x00FF00)
        XCTAssertEqual(Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1).yeelightRGBValue, 0x0000FF)
    }

    func testCreatesColorFromHSVValues() {
        XCTAssertEqual(Color(yeelightHSV: YeelightHSV(hue: 0, saturation: 1, value: 1)).yeelightRGBValue, 0xFF0000)
        XCTAssertEqual(Color(yeelightHSV: YeelightHSV(hue: 120, saturation: 1, value: 1)).yeelightRGBValue, 0x00FF00)
        XCTAssertEqual(Color(yeelightHSV: YeelightHSV(hue: 240, saturation: 1, value: 1)).yeelightRGBValue, 0x0000FF)
        XCTAssertEqual(Color(yeelightHSV: YeelightHSV(hue: 180, saturation: 1, value: 1)).yeelightRGBValue, 0x00FFFF)
    }

    func testReadsHSVValuesFromColor() {
        let redHSV = Color(yeelightRGB: 0xFF0000).yeelightHSVValue
        XCTAssertLessThanOrEqual(angularDistance(redHSV.hue, 0), 1)
        XCTAssertEqual(redHSV.saturation, 1, accuracy: 0.01)
        XCTAssertEqual(redHSV.value, 1, accuracy: 0.01)

        let cyanHSV = Color(yeelightRGB: 0x00FFFF).yeelightHSVValue
        XCTAssertEqual(cyanHSV.hue, 180, accuracy: 0.5)
        XCTAssertEqual(cyanHSV.saturation, 1, accuracy: 0.01)
        XCTAssertEqual(cyanHSV.value, 1, accuracy: 0.01)
    }

    func testRoundTripsRGBThroughHSV() {
        let original = Color(yeelightRGB: 0x3366CC)
        let reconstructed = Color(yeelightHSV: original.yeelightHSVValue)

        XCTAssertEqual(reconstructed.yeelightRGBValue, 0x3366CC)
    }

    func testColorWheelMapsCenterToZeroSaturation() {
        let size = CGSize(width: 200, height: 200)
        let hsv = ColorWheelMath.hsv(at: CGPoint(x: 100, y: 100), in: size, fallbackHue: 42)

        XCTAssertEqual(hsv.hue, 42, accuracy: 0.001)
        XCTAssertEqual(hsv.saturation, 0, accuracy: 0.001)
        XCTAssertEqual(hsv.value, 1, accuracy: 0.001)
    }

    func testColorWheelMapsCardinalPointsToHue() {
        let size = CGSize(width: 200, height: 200)

        XCTAssertLessThanOrEqual(angularDistance(ColorWheelMath.hsv(at: CGPoint(x: 200, y: 100), in: size).hue, 0), 0.5)
        XCTAssertEqual(ColorWheelMath.hsv(at: CGPoint(x: 100, y: 200), in: size).hue, 90, accuracy: 0.5)
        XCTAssertEqual(ColorWheelMath.hsv(at: CGPoint(x: 0, y: 100), in: size).hue, 180, accuracy: 0.5)
        XCTAssertEqual(ColorWheelMath.hsv(at: CGPoint(x: 100, y: 0), in: size).hue, 270, accuracy: 0.5)
    }

    func testColorWheelRoundTripsHSVToPoint() {
        let size = CGSize(width: 200, height: 200)
        let original = YeelightHSV(hue: 203, saturation: 0.72, value: 0.86)
        let point = ColorWheelMath.point(for: original, in: size)
        let reconstructed = ColorWheelMath.hsv(at: point, in: size)

        XCTAssertLessThanOrEqual(angularDistance(reconstructed.hue, original.hue), 0.5)
        XCTAssertEqual(reconstructed.saturation, original.saturation, accuracy: 0.001)
        XCTAssertEqual(reconstructed.value, 1, accuracy: 0.001)
    }

    func testPresetSwatchRGBUsesColorAndHSVValues() {
        XCTAssertEqual(LightPreset.warmAmber.swatchRGB, 0xFF9A2E)
        XCTAssertNil(LightPreset.reading.swatchRGB)

        let hsvRed = LightPreset(id: "hsv-red", title: "HSV Red", kind: .hsv, hue: 0, saturation: 100)
        let hsvCyan = LightPreset(id: "hsv-cyan", title: "HSV Cyan", kind: .hsv, hue: 180, saturation: 100)

        XCTAssertEqual(hsvRed.swatchRGB, 0xFF0000)
        XCTAssertEqual(hsvCyan.swatchRGB, 0x00FFFF)
    }

    private func angularDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}
