import AppKit
import SwiftUI

struct ColorWheelView: View {
    @Environment(\.displayScale) private var displayScale
    @State private var wheelImage: Image?

    let hsv: YeelightHSV
    let onChange: (YeelightHSV) -> Void

    private let diameter: CGFloat = 190
    private let markerSize: CGFloat = 16

    private var displayHSV: YeelightHSV {
        YeelightHSV(hue: hsv.hue, saturation: hsv.saturation, value: 1)
    }

    var body: some View {
        ZStack {
            Group {
                if let wheelImage {
                    wheelImage.resizable()
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                Circle().stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            }

            Circle()
                .fill(Color(yeelightHSV: displayHSV))
                .frame(width: markerSize, height: markerSize)
                .overlay { Circle().stroke(Color.white.opacity(0.92), lineWidth: 2) }
                .overlay { Circle().stroke(Color.black.opacity(0.35), lineWidth: 1) }
                .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
                .position(ColorWheelMath.point(
                    for: displayHSV,
                    in: CGSize(width: diameter, height: diameter)
                ))
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in updateColor(at: value.location) }
        )
        .accessibilityLabel("Color wheel")
        .task(id: Int((diameter * displayScale).rounded())) {
            wheelImage = await ColorWheelImageCache.shared.image(
                diameter: diameter,
                scale: displayScale
            )
        }
    }

    private func updateColor(at location: CGPoint) {
        onChange(ColorWheelMath.hsv(
            at: location,
            in: CGSize(width: diameter, height: diameter),
            fallbackHue: hsv.hue
        ))
    }
}

@MainActor
private final class ColorWheelImageCache {
    static let shared = ColorWheelImageCache()

    private struct Key: Hashable {
        var pixelDiameter: Int
    }

    private var images: [Key: Image] = [:]

    func image(diameter: CGFloat, scale: CGFloat) async -> Image {
        let pixelDiameter = max(1, Int((diameter * max(scale, 1)).rounded()))
        let key = Key(pixelDiameter: pixelDiameter)

        if let image = images[key] {
            return image
        }

        let pixels = await Task.detached(priority: .userInitiated) {
            Self.makePixelData(pixelDiameter: pixelDiameter)
        }.value

        guard let cgImage = makeCGImage(pixelDiameter: pixelDiameter, pixels: pixels) else {
            return Image(systemName: "circle")
        }

        let image = Image(nsImage: NSImage(
            cgImage: cgImage,
            size: CGSize(width: diameter, height: diameter)
        ))
        images[key] = image
        return image
    }

    nonisolated private static func makePixelData(pixelDiameter: Int) -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = pixelDiameter * bytesPerPixel
        let center = Double(pixelDiameter - 1) / 2
        let radius = max(center, 0.0001)
        var pixels = [UInt8](repeating: 0, count: pixelDiameter * bytesPerRow)

        for y in 0..<pixelDiameter {
            for x in 0..<pixelDiameter {
                let dx = Double(x) - center
                let dy = Double(y) - center
                let distance = hypot(dx, dy)

                guard distance <= radius else {
                    continue
                }

                var hue = atan2(dy, dx) * 180 / Double.pi
                if hue < 0 {
                    hue += 360
                }

                let saturation = min(distance / radius, 1)
                let (red, green, blue) = rgb(hue: hue, saturation: saturation, value: 1)
                let index = y * bytesPerRow + x * bytesPerPixel
                pixels[index] = red
                pixels[index + 1] = green
                pixels[index + 2] = blue
                pixels[index + 3] = 255
            }
        }

        return Data(pixels)
    }

    private func makeCGImage(pixelDiameter: Int, pixels: Data) -> CGImage? {
        let bytesPerRow = pixelDiameter * 4
        guard let provider = CGDataProvider(data: pixels as CFData) else {
            return nil
        }

        return CGImage(
            width: pixelDiameter,
            height: pixelDiameter,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    nonisolated private static func rgb(
        hue: Double,
        saturation: Double,
        value: Double
    ) -> (UInt8, UInt8, UInt8) {
        let chroma = value * saturation
        let huePrime = hue / 60
        let x = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))

        let rgb: (Double, Double, Double)
        switch huePrime {
        case 0..<1:
            rgb = (chroma, x, 0)
        case 1..<2:
            rgb = (x, chroma, 0)
        case 2..<3:
            rgb = (0, chroma, x)
        case 3..<4:
            rgb = (0, x, chroma)
        case 4..<5:
            rgb = (x, 0, chroma)
        default:
            rgb = (chroma, 0, x)
        }

        let match = value - chroma
        return (
            UInt8(((rgb.0 + match) * 255).rounded().clamped(to: 0...255)),
            UInt8(((rgb.1 + match) * 255).rounded().clamped(to: 0...255)),
            UInt8(((rgb.2 + match) * 255).rounded().clamped(to: 0...255))
        )
    }
}
