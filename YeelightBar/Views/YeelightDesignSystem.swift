import SwiftUI

enum YeelightDesignTokens {
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24

    static let accent = Color(
        red: 1,
        green: 154.0 / 255.0,
        blue: 46.0 / 255.0
    )
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    static let minimumPopoverWidth = 360.0
    static let defaultPopoverWidth = 400.0
    static let maximumPopoverWidth = 520.0

    static let sleepTimerWidth: CGFloat = 480
    static let sleepTimerHeight: CGFloat = 520
    static let activeSleepTimerHeight: CGFloat = 600

    static let surfaceCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10

    static var surfaceShape: ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(surfaceCornerRadius)),
            isUniform: true
        )
    }

    static var controlShape: ConcentricRectangle {
        ConcentricRectangle(
            corners: .concentric(minimum: .fixed(controlCornerRadius)),
            isUniform: true
        )
    }
}

enum GlassSurfaceStyle {
    case regular
    case interactive
    case tinted(Color)

    var glass: Glass {
        switch self {
        case .regular:
            return .regular
        case .interactive:
            return .regular.interactive()
        case .tinted(let color):
            return .regular.tint(color.opacity(0.10)).interactive()
        }
    }
}

extension View {
    func yeelightGlass(_ style: GlassSurfaceStyle = .regular) -> some View {
        glassEffect(style.glass, in: YeelightDesignTokens.surfaceShape)
    }

    func yeelightPrimaryButtonStyle() -> some View {
        buttonStyle(.glassProminent)
            .tint(YeelightDesignTokens.accent)
    }
}

struct GlassSection<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let style: GlassSurfaceStyle
    @ViewBuilder private let content: Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        style: GlassSurfaceStyle = .regular,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceM) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
                    if let title {
                        Text(title)
                            .font(.headline)
                    }

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(YeelightDesignTokens.spaceL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .yeelightGlass(style)
    }
}

struct UtilitySheetHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: YeelightDesignTokens.spaceM) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(YeelightDesignTokens.accent)
                .frame(width: 32, height: 32)
                .background(YeelightDesignTokens.accent.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum DeviceCardConnectionState: Equatable {
    case online
    case offline
    case unknown

    var isOnline: Bool {
        self == .online
    }

    var title: String {
        switch self {
        case .online:
            return "Online"
        case .offline:
            return "Offline"
        case .unknown:
            return "Status unknown"
        }
    }

    var color: Color {
        switch self {
        case .online:
            return YeelightDesignTokens.success
        case .offline:
            return Color.secondary
        case .unknown:
            return YeelightDesignTokens.warning
        }
    }
}

struct DeviceCardSnapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let model: String
    let endpoint: String
    let isSelected: Bool
    let connectionState: DeviceCardConnectionState
    let power: PowerState
    let brightness: Int
    let colorMode: ColorMode
    let colorTemperature: Int
    let rgb: Int
    let hue: Int
    let saturation: Int

    init(device: YeelightDevice, selectedDeviceID: String?) {
        id = device.id
        name = device.displayName
        model = device.model
        endpoint = "\(device.host):\(device.port)"
        isSelected = device.id == selectedDeviceID
        if device.state.online {
            connectionState = .online
        } else if device.state.power == .unknown {
            connectionState = .unknown
        } else {
            connectionState = .offline
        }
        power = device.state.power
        brightness = device.state.brightness
        colorMode = device.state.colorMode
        colorTemperature = device.state.colorTemperature
        rgb = device.state.rgb
        hue = device.state.hue
        saturation = device.state.saturation
    }

    var isOnline: Bool {
        connectionState.isOnline
    }

    var statusTitle: String {
        switch connectionState {
        case .unknown:
            return connectionState.title
        case .offline:
            switch power {
            case .on:
                return "Offline · last on at \(brightness)%"
            case .off:
                return "Offline · last off"
            case .unknown:
                return connectionState.title
            }
        case .online:
            break
        }

        switch power {
        case .on:
            return "On · \(brightness)%"
        case .off:
            return "Off"
        case .unknown:
            return "Online"
        }
    }

    var statusColor: Color {
        connectionState.color
    }

    var ambientColor: Color {
        LightAppearanceColorResolver.color(for: self)
    }
}

enum LightAppearanceColorResolver {
    static func color(for snapshot: DeviceCardSnapshot) -> Color {
        guard snapshot.isOnline else {
            return YeelightDesignTokens.accent
        }

        switch snapshot.colorMode {
        case .rgb:
            return Color(yeelightRGB: snapshot.rgb)
        case .hsv:
            return Color(
                hue: Double(snapshot.hue) / 360.0,
                saturation: Double(snapshot.saturation) / 100.0,
                brightness: 1
            )
        case .colorTemperature:
            return temperatureColor(kelvin: snapshot.colorTemperature)
        case .unknown:
            return YeelightDesignTokens.accent
        }
    }

    static func temperatureColor(kelvin: Int) -> Color {
        let normalized = Double(kelvin.clamped(to: 1700...6500) - 1700) / 4800.0
        let warm = (red: 1.0, green: 0.49, blue: 0.16)
        let cool = (red: 0.64, green: 0.80, blue: 1.0)

        return Color(
            red: warm.red + (cool.red - warm.red) * normalized,
            green: warm.green + (cool.green - warm.green) * normalized,
            blue: warm.blue + (cool.blue - warm.blue) * normalized
        )
    }
}
