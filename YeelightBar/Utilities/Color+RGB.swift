import AppKit
import SwiftUI

struct YeelightHSV: Equatable {
    var hue: Double
    var saturation: Double
    var value: Double

    init(hue: Double, saturation: Double, value: Double) {
        self.hue = (hue.isFinite ? hue : 0).clamped(to: 0...359)
        self.saturation = (saturation.isFinite ? saturation : 0).clamped(to: 0...1)
        self.value = (value.isFinite ? value : 0).clamped(to: 0...1)
    }
}

enum ColorWheelMath {
    static func hsv(at point: CGPoint, in size: CGSize, fallbackHue: Double = 0) -> YeelightHSV {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(min(size.width, size.height) / 2, 0.0001)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        let saturation = Double((distance / radius).clamped(to: 0...1))

        guard saturation > 0.0001 else {
            return YeelightHSV(hue: fallbackHue, saturation: 0, value: 1)
        }

        var hue = atan2(Double(dy), Double(dx)) * 180 / Double.pi
        if hue < 0 {
            hue += 360
        }

        return YeelightHSV(hue: hue, saturation: saturation, value: 1)
    }

    static func point(for hsv: YeelightHSV, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2
        let radians = hsv.hue * Double.pi / 180
        let distance = CGFloat(hsv.saturation) * radius

        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * distance,
            y: center.y + CGFloat(sin(radians)) * distance
        )
    }
}

extension Color {
    init(yeelightRGB: Int) {
        let red = Double((yeelightRGB >> 16) & 0xFF) / 255
        let green = Double((yeelightRGB >> 8) & 0xFF) / 255
        let blue = Double(yeelightRGB & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    init(yeelightHSV: YeelightHSV) {
        self.init(
            hue: yeelightHSV.hue / 360,
            saturation: yeelightHSV.saturation,
            brightness: yeelightHSV.value
        )
    }

    var yeelightNSColor: NSColor {
        NSColor(self).usingColorSpace(.sRGB) ?? .white
    }

    var yeelightRGBValue: Int {
        let nsColor = yeelightNSColor
        let red = Int((nsColor.redComponent * 255).rounded()).clamped(to: 0...255)
        let green = Int((nsColor.greenComponent * 255).rounded()).clamped(to: 0...255)
        let blue = Int((nsColor.blueComponent * 255).rounded()).clamped(to: 0...255)
        return (red << 16) + (green << 8) + blue
    }

    var yeelightHSVValue: YeelightHSV {
        let nsColor = yeelightNSColor
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        return YeelightHSV(
            hue: Double(hue) * 360,
            saturation: Double(saturation),
            value: Double(brightness)
        )
    }
}
