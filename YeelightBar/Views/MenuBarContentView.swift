import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if state.devices.isEmpty {
                emptyState
            } else {
                controls
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: state.popoverWidth)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("YeelightBar", systemImage: state.status.symbolName)
                .font(.headline)

            Spacer()

            Button {
                state.discover()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Discover devices")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.status.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Works with Yeelight LAN-compatible Wi-Fi lights. Xiaomi/Mijia devices only work if they expose Yeelight LAN Control on the local network.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !state.discoveredCandidates.isEmpty {
                Divider()
                    .padding(.vertical, 2)
                Text("Discovered Bulbs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(state.discoveredCandidates.prefix(3)) { candidate in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(candidate.device.displayName)
                                .lineLimit(1)
                            Text("\(candidate.device.host):\(candidate.device.port)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(candidate.endpointChanged ? "Approve" : "Add") {
                            state.trustDiscoveredCandidate(id: candidate.id)
                        }
                        .controlSize(.small)
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            manualDeviceForm
        }
    }

    private var manualDeviceForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual IP")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("192.168.1.42", text: Binding(
                    get: { state.manualHost },
                    set: { state.manualHost = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if state.canAddManualDevice {
                        state.addManualDevice()
                    }
                }

                TextField("55443", text: Binding(
                    get: { state.manualPort },
                    set: { state.manualPort = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .onSubmit {
                    if state.canAddManualDevice {
                        state.addManualDevice()
                    }
                }

                Button {
                    state.addManualDevice()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!state.canAddManualDevice)
                .help("Add manual device")
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("Device", selection: Binding(
                    get: { state.selectedDeviceID },
                    set: { state.selectDevice(id: $0) }
                )) {
                    ForEach(state.devices) { device in
                        Text(device.displayName).tag(Optional(device.id))
                    }
                }

                Button(role: .destructive) {
                    state.removeSelectedDevice()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(!state.hasSelectedDevice)
                .help("Remove selected device")
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if state.controlDisplayMode == .detailed, !state.selectedDeviceEndpoint.isEmpty {
                        Text(state.selectedDeviceEndpoint)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Toggle("Power", isOn: Binding(
                    get: { state.isPowerOn },
                    set: { state.setPower($0) }
                ))
                .toggleStyle(.switch)
                .disabled(!state.canControlSelectedDevice)
            }

            controlSlider(
                title: "Brightness",
                systemImage: "sun.max",
                value: Binding(
                    get: { state.brightness },
                    set: { state.setBrightness($0) }
                ),
                range: 1...100,
                valueLabel: "\(Int(state.brightness.rounded()))%"
            )

            lightModeControls

            Divider()
                .padding(.vertical, 2)

            if state.controlDisplayMode == .detailed {
                manualDeviceForm
            }
        }
        .disabled(!state.hasSelectedDevice)
    }

    private var lightModeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Light mode", selection: Binding(
                get: { state.lightControlMode },
                set: { state.setLightControlMode($0) }
            )) {
                ForEach(LightControlMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!state.canControlSelectedDevice)

            switch state.lightControlMode {
            case .white:
                whiteTemperatureControl
            case .color:
                colorControl
            case .flow:
                flowControl
            }
        }
    }

    private var whiteTemperatureControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("White Temperature", systemImage: "thermometer.sun")
                    .lineLimit(1)

                Spacer()

                Text("\(Int(state.colorTemperature.rounded()))K")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: Binding(
                get: { state.colorTemperature },
                set: { state.setColorTemperature($0) }
            ), in: 1700...6500)
            .disabled(!state.canControlSelectedDevice)

            HStack {
                Text("Warm")
                Spacer()
                Text("Cool")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            presetChips(state.whitePresets)
        }
    }

    private var colorControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Color", systemImage: "paintpalette")
                    .font(.caption)

                Spacer()
            }

            Button {
                state.toggleColorEditor()
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(state.selectedColor)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Circle()
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        }
                        .shadow(color: state.selectedColor.opacity(0.18), radius: 3, x: 0, y: 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Selected color")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text("#\(String(format: "%06X", state.selectedColor.yeelightRGBValue))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Image(systemName: state.isColorEditingActive ? "chevron.up" : "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.secondary.opacity(state.isColorEditingActive ? 0.14 : 0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.secondary.opacity(state.isColorEditingActive ? 0.22 : 0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(!state.canControlSelectedDevice || !state.showColorControl || !state.selectedDeviceSupportsColor)
            .help("Edit selected color")

            if state.isColorEditingActive {
                inlineColorEditor
            }

            colorPresetSwatches(state.colorPresets)
        }
    }

    private var inlineColorEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Pick Color")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    state.closeColorEditor()
                }
                .controlSize(.small)
            }

            HStack {
                Spacer()
                ColorWheelView(hsv: state.selectedColor.yeelightHSVValue) { hsv in
                    state.setHueSaturation(hue: hsv.hue, saturation: hsv.saturation)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        }
    }

    private func colorPresetSwatches(_ presets: [LightPreset]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if !presets.isEmpty {
                Text("Quick Colors")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 70), spacing: 8)
                ], alignment: .leading, spacing: 8) {
                    ForEach(presets) { preset in
                        Button {
                            state.applyPreset(id: preset.id)
                        } label: {
                            VStack(spacing: 5) {
                                Circle()
                                    .fill(Color(yeelightRGB: preset.swatchRGB ?? preset.rgb))
                                    .frame(width: 26, height: 26)
                                    .overlay {
                                        Circle()
                                            .stroke(Color.secondary.opacity(0.28), lineWidth: 1)
                                    }
                                    .shadow(color: Color(yeelightRGB: preset.swatchRGB ?? preset.rgb).opacity(0.16), radius: 2, x: 0, y: 1)

                                Text(preset.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity)
                            .background {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.secondary.opacity(0.10))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(!state.canControlSelectedDevice || !state.selectedDeviceSupportsColor)
                        .help(preset.summary)
                    }
                }
            } else {
                Text("No color presets.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var flowControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Flows", systemImage: "waveform")
                    .font(.caption)

                Spacer()

                if state.selectedDeviceIsFlowing {
                    Label("Flowing", systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Mode", selection: Binding(
                get: { state.selectedFlowPresetID },
                set: { state.setSelectedPresetID($0) }
            )) {
                ForEach(state.flowPresets) { preset in
                    Text(preset.title).tag(preset.id)
                }
            }
            .labelsHidden()
            .disabled(state.flowPresets.isEmpty)

            Text(state.selectedFlowPresetSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button {
                    state.applyPreset(id: state.selectedFlowPresetID)
                } label: {
                    Label("Apply", systemImage: "play.fill")
                }
                .disabled(!state.canControlSelectedDevice || state.flowPresets.isEmpty)

                Button {
                    state.stopFlow()
                } label: {
                    Label("Stop Flow", systemImage: "stop.fill")
                }
                .disabled(!state.canControlSelectedDevice || !state.selectedDeviceIsFlowing)
            }
            .buttonStyle(.borderless)

            if state.controlDisplayMode == .detailed, !state.favoritePresets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Favorites")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(state.favoritePresets.prefix(4)) { preset in
                        Button {
                            state.applyPreset(id: preset.id)
                        } label: {
                            Label(preset.title, systemImage: preset.symbolName)
                                .lineLimit(1)
                        }
                        .buttonStyle(.borderless)
                        .disabled(!state.canControlSelectedDevice)
                    }
                }
            }
        }
    }

    private func presetChips(_ presets: [LightPreset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !presets.isEmpty {
                Text("Presets")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 92), spacing: 6)
                ], alignment: .leading, spacing: 6) {
                    ForEach(presets) { preset in
                        Button {
                            state.applyPreset(id: preset.id)
                        } label: {
                            Label(preset.title, systemImage: preset.symbolName)
                                .font(.caption)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!state.canControlSelectedDevice)
                        .help(preset.summary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                state.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

            Button {
                state.checkForUpdates()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Check for Updates…")
            .accessibilityLabel("Check for Updates")

            Spacer()

            Button {
                state.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
    }

    private func controlSlider(
        title: String,
        systemImage: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                Spacer()
                Text(valueLabel)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: value, in: range)
                .disabled(!state.canControlSelectedDevice)
        }
    }
}

private struct ColorWheelView: View {
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
                    wheelImage
                        .resizable()
                } else {
                    Circle()
                        .fill(.quaternary)
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            }

            Circle()
                .fill(Color(yeelightHSV: displayHSV))
                .frame(width: markerSize, height: markerSize)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.92), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 2, x: 0, y: 1)
                .position(ColorWheelMath.point(for: displayHSV, in: CGSize(width: diameter, height: diameter)))
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    updateColor(at: value.location)
                }
        )
        .accessibilityLabel("Color wheel")
        .task(id: Int((diameter * displayScale).rounded())) {
            wheelImage = await ColorWheelImageCache.shared.image(diameter: diameter, scale: displayScale)
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

    nonisolated private static func rgb(hue: Double, saturation: Double, value: Double) -> (UInt8, UInt8, UInt8) {
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
