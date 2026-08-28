import SwiftUI

struct SleepTimerActiveStatusCard: View {
    let title: String
    let detail: String
    let accessibilityLabel: String
    let canCancel: Bool
    let unavailableReason: String
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: YeelightDesignTokens.spaceM) {
            Image(systemName: "moon.zzz.fill")
                .foregroundStyle(YeelightDesignTokens.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            Spacer()

            Button("Cancel Timer", role: .destructive, action: onCancel)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(!canCancel)
                .help(canCancel ? "Cancel the selected light's sleep timer" : unavailableReason)
        }
        .padding(YeelightDesignTokens.spaceM)
        .yeelightGlass(.tinted(YeelightDesignTokens.accent))
    }
}

struct SleepTimerAppearancePreview<Icon: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let icon: Icon

    init(
        title: String,
        summary: String,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.summary = summary
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: YeelightDesignTokens.spaceM) {
            icon

            VStack(alignment: .leading, spacing: YeelightDesignTokens.spaceXS) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, YeelightDesignTokens.spaceXS)
        .accessibilityElement(children: .combine)
    }
}

struct SleepTimerNoticeBanner: View {
    let message: String
    let systemImage: String
    let color: Color
    let accessibilityLabel: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibilityLabel)
    }
}

enum SleepTimerDuration: String, CaseIterable, Identifiable {
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minutes15: return "15 min"
        case .minutes30: return "30 min"
        case .minutes45: return "45 min"
        case .minutes60: return "1 hr"
        case .custom: return "Custom"
        }
    }

    var minutes: Int? {
        switch self {
        case .minutes15: return 15
        case .minutes30: return 30
        case .minutes45: return 45
        case .minutes60: return 60
        case .custom: return nil
        }
    }

    init?(minutes: Int) {
        switch minutes {
        case 15: self = .minutes15
        case 30: self = .minutes30
        case 45: self = .minutes45
        case 60: self = .minutes60
        default: return nil
        }
    }
}

enum SleepTimerAppearanceChoice: String, Hashable {
    case current
    case warmDim
    case softRose
    case preset
}

enum SleepTimerNotice {
    case warning(String)
    case error(String)

    var message: String {
        switch self {
        case .warning(let message), .error(let message): return message
        }
    }

    var symbolName: String {
        switch self {
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .warning: return .orange
        case .error: return .red
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .warning(let message): return "Warning: \(message)"
        case .error(let message): return "Error: \(message)"
        }
    }
}
