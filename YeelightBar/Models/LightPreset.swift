import Foundation

enum LightPresetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case color
    case colorTemperature
    case hsv
    case flow

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .color:
            return "Color"
        case .colorTemperature:
            return "Temperature"
        case .hsv:
            return "HSV"
        case .flow:
            return "Flow"
        }
    }
}

struct CurrentLightLook: Equatable, Sendable {
    enum Value: Equatable, Sendable {
        case color(rgb: Int)
        case colorTemperature(Int)
        case hsv(hue: Int, saturation: Int)
    }

    let value: Value
    let brightness: Int

    init(value: Value, brightness: Int) {
        switch value {
        case .color(let rgb):
            self.value = .color(rgb: rgb.clamped(to: 0...0xFFFFFF))
        case .colorTemperature(let temperature):
            self.value = .colorTemperature(temperature.clamped(to: 1700...6500))
        case .hsv(let hue, let saturation):
            self.value = .hsv(
                hue: hue.clamped(to: 0...359),
                saturation: saturation.clamped(to: 0...100)
            )
        }

        self.brightness = brightness.clamped(to: 1...100)
    }

    var summary: String {
        makePreset(id: "preview", title: "Preview").summary
    }

    var symbolName: String {
        makePreset(id: "preview", title: "Preview").symbolName
    }

    var swatchRGB: Int? {
        makePreset(id: "preview", title: "Preview").swatchRGB
    }

    func makePreset(id: String, title: String) -> LightPreset {
        switch value {
        case .color(let rgb):
            return LightPreset(
                id: id,
                title: title,
                kind: .color,
                brightness: brightness,
                rgb: rgb
            )
        case .colorTemperature(let temperature):
            return LightPreset(
                id: id,
                title: title,
                kind: .colorTemperature,
                brightness: brightness,
                colorTemperature: temperature
            )
        case .hsv(let hue, let saturation):
            return LightPreset(
                id: id,
                title: title,
                kind: .hsv,
                brightness: brightness,
                hue: hue,
                saturation: saturation
            )
        }
    }
}

enum FlowStopAction: Int, CaseIterable, Codable, Identifiable, Sendable {
    case recover = 0
    case stay = 1
    case turnOff = 2

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .recover:
            return "Recover"
        case .stay:
            return "Stay"
        case .turnOff:
            return "Turn Off"
        }
    }
}

enum FlowStepMode: Int, CaseIterable, Codable, Identifiable, Sendable {
    case color = 1
    case colorTemperature = 2
    case sleep = 7

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .color:
            return "Color"
        case .colorTemperature:
            return "Temperature"
        case .sleep:
            return "Sleep"
        }
    }
}

struct FlowStep: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var mode: FlowStepMode
    var duration: Int
    var rgb: Int
    var colorTemperature: Int
    var brightness: Int?

    init(
        id: UUID = UUID(),
        mode: FlowStepMode,
        duration: Int,
        rgb: Int = 0xFFFFFF,
        colorTemperature: Int = 4000,
        brightness: Int? = nil
    ) {
        self.id = id
        self.mode = mode
        self.duration = duration.clamped(to: 50...3_600_000)
        self.rgb = rgb.clamped(to: 0...0xFFFFFF)
        self.colorTemperature = colorTemperature.clamped(to: 1700...6500)
        self.brightness = brightness.map { $0.clamped(to: 1...100) }
    }

    var sanitized: FlowStep {
        FlowStep(
            id: id,
            mode: mode,
            duration: duration,
            rgb: rgb,
            colorTemperature: colorTemperature,
            brightness: brightness
        )
    }

    var encodedTuple: [Int] {
        let brightnessValue = brightness ?? -1

        switch mode {
        case .color:
            return [duration.clamped(to: 50...3_600_000), mode.rawValue, rgb.clamped(to: 0...0xFFFFFF), brightnessValue]
        case .colorTemperature:
            return [duration.clamped(to: 50...3_600_000), mode.rawValue, colorTemperature.clamped(to: 1700...6500), brightnessValue]
        case .sleep:
            return [duration.clamped(to: 50...3_600_000), mode.rawValue, 0, 0]
        }
    }

    static func color(_ rgb: Int, brightness: Int? = 100, duration: Int = 500) -> FlowStep {
        FlowStep(mode: .color, duration: duration, rgb: rgb, brightness: brightness)
    }

    static func colorTemperature(_ temperature: Int, brightness: Int? = 100, duration: Int = 500) -> FlowStep {
        FlowStep(mode: .colorTemperature, duration: duration, colorTemperature: temperature, brightness: brightness)
    }

    static func sleep(_ duration: Int) -> FlowStep {
        FlowStep(mode: .sleep, duration: duration)
    }
}

struct ColorFlow: Codable, Equatable, Sendable {
    static let maximumCount = 10_000

    var count: Int
    var stopAction: FlowStopAction
    var steps: [FlowStep]

    init(count: Int = 0, stopAction: FlowStopAction = .recover, steps: [FlowStep]) {
        self.count = count.clamped(to: 0...Self.maximumCount)
        self.stopAction = stopAction
        self.steps = steps.map(\.sanitized)
    }

    var sanitized: ColorFlow {
        ColorFlow(count: count, stopAction: stopAction, steps: steps)
    }

    var expression: String {
        steps
            .flatMap(\.encodedTuple)
            .map(String.init)
            .joined(separator: ",")
    }

    var isValid: Bool {
        !steps.isEmpty && !expression.isEmpty
    }

    static func count(forCycles cycles: Int, stepCount: Int) -> Int? {
        guard cycles > 0, stepCount > 0 else {
            return nil
        }

        let (count, overflow) = cycles.multipliedReportingOverflow(by: stepCount)
        guard !overflow, count <= maximumCount else {
            return nil
        }

        return count
    }
}

struct LightPreset: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var kind: LightPresetKind
    var brightness: Int
    var rgb: Int
    var colorTemperature: Int
    var hue: Int
    var saturation: Int
    var flow: ColorFlow?
    var isBuiltIn: Bool

    init(
        id: String,
        title: String,
        kind: LightPresetKind,
        brightness: Int = 100,
        rgb: Int = 0xFFFFFF,
        colorTemperature: Int = 4000,
        hue: Int = 0,
        saturation: Int = 100,
        flow: ColorFlow? = nil,
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.brightness = brightness.clamped(to: 1...100)
        self.rgb = rgb.clamped(to: 0...0xFFFFFF)
        self.colorTemperature = colorTemperature.clamped(to: 1700...6500)
        self.hue = hue.clamped(to: 0...359)
        self.saturation = saturation.clamped(to: 0...100)
        self.flow = flow?.sanitized
        self.isBuiltIn = isBuiltIn
    }

    var sanitizedCustomCopy: LightPreset {
        LightPreset(
            id: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            brightness: brightness,
            rgb: rgb,
            colorTemperature: colorTemperature,
            hue: hue,
            saturation: saturation,
            flow: flow,
            isBuiltIn: false
        )
    }

    var symbolName: String {
        switch kind {
        case .color:
            return "paintpalette"
        case .colorTemperature:
            return "thermometer.sun"
        case .hsv:
            return "circle.hexagongrid"
        case .flow:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var summary: String {
        switch kind {
        case .color:
            return "RGB #\(String(format: "%06X", rgb)) at \(brightness)%"
        case .colorTemperature:
            return "\(colorTemperature)K at \(brightness)%"
        case .hsv:
            return "Hue \(hue), sat \(saturation), \(brightness)%"
        case .flow:
            guard let flow else {
                return "Invalid flow"
            }

            let stepText = "\(flow.steps.count) \(flow.steps.count == 1 ? "step" : "steps")"
            let playbackText: String

            if flow.count == 0 {
                playbackText = "repeats forever"
            } else if !flow.steps.isEmpty, flow.count.isMultiple(of: flow.steps.count) {
                let cycles = flow.count / flow.steps.count
                playbackText = "\(cycles) \(cycles == 1 ? "cycle" : "cycles")"
            } else {
                playbackText = "\(flow.count) transitions"
            }

            return "\(stepText) · \(playbackText) · \(flow.stopAction.title)"
        }
    }

    var swatchRGB: Int? {
        switch kind {
        case .color:
            return rgb.clamped(to: 0...0xFFFFFF)
        case .hsv:
            return Self.rgbFromHSV(hue: hue, saturation: saturation)
        case .colorTemperature, .flow:
            return nil
        }
    }

    private static func rgbFromHSV(hue: Int, saturation: Int) -> Int {
        let normalizedHue = Double(hue.clamped(to: 0...359)) / 60
        let normalizedSaturation = Double(saturation.clamped(to: 0...100)) / 100
        let chroma = normalizedSaturation
        let x = chroma * (1 - abs(normalizedHue.truncatingRemainder(dividingBy: 2) - 1))
        let m = 1 - chroma

        let components: (Double, Double, Double)
        switch normalizedHue {
        case 0..<1:
            components = (chroma, x, 0)
        case 1..<2:
            components = (x, chroma, 0)
        case 2..<3:
            components = (0, chroma, x)
        case 3..<4:
            components = (0, x, chroma)
        case 4..<5:
            components = (x, 0, chroma)
        default:
            components = (chroma, 0, x)
        }

        let red = Int(((components.0 + m) * 255).rounded()).clamped(to: 0...255)
        let green = Int(((components.1 + m) * 255).rounded()).clamped(to: 0...255)
        let blue = Int(((components.2 + m) * 255).rounded()).clamped(to: 0...255)
        return (red << 16) + (green << 8) + blue
    }

    static let reading = LightPreset(
        id: "builtin-reading",
        title: "Reading",
        kind: .colorTemperature,
        brightness: 80,
        colorTemperature: 4300,
        isBuiltIn: true
    )

    static let relax = LightPreset(
        id: "builtin-relax",
        title: "Relax",
        kind: .colorTemperature,
        brightness: 35,
        colorTemperature: 2700,
        isBuiltIn: true
    )

    static let night = LightPreset(
        id: "builtin-night",
        title: "Night",
        kind: .colorTemperature,
        brightness: 5,
        colorTemperature: 1900,
        isBuiltIn: true
    )

    static let focus = LightPreset(
        id: "builtin-focus",
        title: "Focus",
        kind: .colorTemperature,
        brightness: 100,
        colorTemperature: 5000,
        isBuiltIn: true
    )

    static let movie = LightPreset(
        id: "builtin-movie",
        title: "Movie",
        kind: .color,
        brightness: 20,
        rgb: 0xFF8A30,
        isBuiltIn: true
    )

    static let warmAmber = LightPreset(
        id: "builtin-warm-amber",
        title: "Warm Amber",
        kind: .color,
        brightness: 45,
        rgb: 0xFF9A2E,
        isBuiltIn: true
    )

    static let aqua = LightPreset(
        id: "builtin-aqua",
        title: "Aqua",
        kind: .color,
        brightness: 65,
        rgb: 0x00D6C9,
        isBuiltIn: true
    )

    static let rose = LightPreset(
        id: "builtin-rose",
        title: "Rose",
        kind: .color,
        brightness: 55,
        rgb: 0xFF4F8B,
        isBuiltIn: true
    )

    static let blue = LightPreset(
        id: "builtin-blue",
        title: "Blue",
        kind: .color,
        brightness: 60,
        rgb: 0x2F6BFF,
        isBuiltIn: true
    )

    static let sunrise = LightPreset(
        id: "builtin-sunrise",
        title: "Sunrise",
        kind: .flow,
        flow: ColorFlow(
            count: 4,
            stopAction: .stay,
            steps: [
                .colorTemperature(1900, brightness: 1, duration: 1_000),
                .sleep(20_000),
                .colorTemperature(2700, brightness: 35, duration: 30_000),
                .colorTemperature(4300, brightness: 80, duration: 30_000)
            ]
        ),
        isBuiltIn: true
    )

    static let sunset = LightPreset(
        id: "builtin-sunset",
        title: "Sunset",
        kind: .flow,
        flow: ColorFlow(
            count: 4,
            stopAction: .turnOff,
            steps: [
                .colorTemperature(4300, brightness: 70, duration: 1_000),
                .colorTemperature(3000, brightness: 35, duration: 30_000),
                .colorTemperature(2200, brightness: 10, duration: 30_000),
                .sleep(10_000)
            ]
        ),
        isBuiltIn: true
    )

    static let rainbow = LightPreset(
        id: "builtin-rainbow",
        title: "Rainbow",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0xFF0000, brightness: 80, duration: 800),
                .color(0xFF7F00, brightness: 80, duration: 800),
                .color(0xFFFF00, brightness: 80, duration: 800),
                .color(0x00FF00, brightness: 80, duration: 800),
                .color(0x0000FF, brightness: 80, duration: 800),
                .color(0x8B00FF, brightness: 80, duration: 800)
            ]
        ),
        isBuiltIn: true
    )

    static let candle = LightPreset(
        id: "builtin-candle",
        title: "Candle",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0xFF6A00, brightness: 18, duration: 400),
                .color(0xFFB000, brightness: 35, duration: 450),
                .sleep(350),
                .color(0xFF4A00, brightness: 12, duration: 300)
            ]
        ),
        isBuiltIn: true
    )

    static let calmBreathing = LightPreset(
        id: "builtin-calm-breathing",
        title: "Calm Breathing",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0x2DD4BF, brightness: 22, duration: 1_800),
                .sleep(900),
                .color(0x3B82F6, brightness: 16, duration: 1_800),
                .sleep(900),
                .colorTemperature(2400, brightness: 12, duration: 1_800),
                .sleep(1_200)
            ]
        ),
        isBuiltIn: true
    )

    static let deepFocusPulse = LightPreset(
        id: "builtin-deep-focus-pulse",
        title: "Deep Focus Pulse",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .colorTemperature(4800, brightness: 72, duration: 4_000),
                .sleep(1_200),
                .colorTemperature(5600, brightness: 86, duration: 4_000),
                .sleep(1_200),
                .colorTemperature(5200, brightness: 78, duration: 4_000),
                .sleep(1_600)
            ]
        ),
        isBuiltIn: true
    )

    static let dinnerWarmth = LightPreset(
        id: "builtin-dinner-warmth",
        title: "Dinner Warmth",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .colorTemperature(2200, brightness: 32, duration: 2_400),
                .color(0xFF8A30, brightness: 38, duration: 2_200),
                .colorTemperature(2700, brightness: 42, duration: 2_800),
                .sleep(1_000)
            ]
        ),
        isBuiltIn: true
    )

    static let tvAmbient = LightPreset(
        id: "builtin-tv-ambient",
        title: "TV Ambient",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0x1D4ED8, brightness: 14, duration: 2_500),
                .sleep(800),
                .color(0x7C3AED, brightness: 12, duration: 2_500),
                .sleep(800),
                .color(0xF97316, brightness: 10, duration: 2_500),
                .sleep(1_200)
            ]
        ),
        isBuiltIn: true
    )

    static let partyPulse = LightPreset(
        id: "builtin-party-pulse",
        title: "Party Pulse",
        kind: .flow,
        flow: ColorFlow(
            count: 0,
            stopAction: .recover,
            steps: [
                .color(0xFF005C, brightness: 90, duration: 450),
                .color(0x00D6C9, brightness: 86, duration: 450),
                .color(0x7C3AED, brightness: 88, duration: 450),
                .color(0xFACC15, brightness: 82, duration: 450),
                .sleep(250)
            ]
        ),
        isBuiltIn: true
    )

    static let findBulb = LightPreset(
        id: "builtin-find-bulb",
        title: "Find Bulb",
        kind: .flow,
        flow: ColorFlow(
            count: 8,
            stopAction: .recover,
            steps: [
                .colorTemperature(6500, brightness: 100, duration: 250),
                .sleep(150),
                .color(0xFF0000, brightness: 100, duration: 250),
                .sleep(150),
                .colorTemperature(6500, brightness: 100, duration: 250),
                .sleep(150),
                .color(0x006CFF, brightness: 100, duration: 250),
                .sleep(250)
            ]
        ),
        isBuiltIn: true
    )

    static let builtIns: [LightPreset] = [
        .reading,
        .relax,
        .night,
        .focus,
        .movie,
        .warmAmber,
        .aqua,
        .rose,
        .blue,
        .sunrise,
        .sunset,
        .rainbow,
        .candle,
        .calmBreathing,
        .deepFocusPulse,
        .dinnerWarmth,
        .tvAmbient,
        .partyPulse,
        .findBulb
    ]

    static let defaultFavoriteIDs = [
        LightPreset.reading.id,
        LightPreset.relax.id,
        LightPreset.night.id,
        LightPreset.sunrise.id,
        LightPreset.rainbow.id
    ]
}
