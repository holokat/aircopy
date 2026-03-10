import SwiftUI

enum AirCopyTheme {
    static func background(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .light {
            return LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.95, blue: 0.97),
                    Color(red: 0.90, green: 0.92, blue: 0.95),
                    Color(red: 0.95, green: 0.96, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.08, blue: 0.09),
                Color(red: 0.12, green: 0.11, blue: 0.12),
                Color(red: 0.09, green: 0.09, blue: 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func panelFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? Color.white.opacity(0.78) : Color.white.opacity(0.05)
    }

    static func insetFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.86, green: 0.89, blue: 0.93).opacity(0.9)
            : Color(red: 0.18, green: 0.18, blue: 0.19).opacity(0.92)
    }

    static func panelStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.70, green: 0.76, blue: 0.84).opacity(0.52)
            : Color.white.opacity(0.09)
    }

    static func divider(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.68, green: 0.74, blue: 0.82).opacity(0.5)
            : Color.white.opacity(0.1)
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.22, green: 0.30, blue: 0.42)
            : Color.white.opacity(0.94)
    }

    static func accentSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.34, green: 0.42, blue: 0.54)
            : Color.white.opacity(0.7)
    }

    static func success(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.18, green: 0.64, blue: 0.38)
            : Color(red: 0.30, green: 0.84, blue: 0.50)
    }

    static func buttonTint(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light
            ? Color(red: 0.27, green: 0.36, blue: 0.48)
            : Color(red: 0.23, green: 0.23, blue: 0.24)
    }

    static let panelShadow = Color.black.opacity(0.14)

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? Color(red: 0.12, green: 0.16, blue: 0.22) : .white
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .light ? Color(red: 0.28, green: 0.35, blue: 0.44) : .white.opacity(0.9)
    }
}

struct AirCopyPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AirCopyTheme.panelFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(AirCopyTheme.panelStroke(for: colorScheme), lineWidth: 1)
                    )
                    .shadow(color: AirCopyTheme.panelShadow, radius: colorScheme == .light ? 14 : 18, y: 8)
            )
    }
}

extension View {
    func airCopyPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(AirCopyPanelModifier(cornerRadius: cornerRadius))
    }
}
