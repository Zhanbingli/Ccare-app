import SwiftUI

enum AppSpacing {
    static let xxSmall: CGFloat = 4
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
}

enum AppRadius {
    static let panel: CGFloat = 16
    static let card: CGFloat = 24
    static let hero: CGFloat = 28
}

enum AppSemanticColor {
    static let info = Color.accentColor
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}

struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .shadow(color: cardShadow, radius: 14, x: 0, y: 8)
    }

    private var cardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.82)
    }

    private var cardStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.05)
    }

    private var cardShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color(red: 0.15, green: 0.22, blue: 0.28).opacity(0.10)
    }
}

struct TintedCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let content: Content
    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    var body: some View {
        content
            .padding(AppSpacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(colorScheme == .dark ? 0.26 : 0.20),
                                tint.opacity(colorScheme == .dark ? 0.12 : 0.09),
                                cardBase.opacity(colorScheme == .dark ? 0.88 : 0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.hero, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.26 : 0.20), lineWidth: 1.2)
            )
            .shadow(color: tint.opacity(colorScheme == .dark ? 0.18 : 0.16), radius: 14, x: 0, y: 8)
    }

    private var cardBase: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
}

struct AppBadge: View {
    let text: String
    let tint: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .appFont(.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.xSmall)
        .padding(.vertical, 5)
        .frame(minHeight: 28)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.11))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 0.9)
        )
    }
}

struct InsetPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color?
    let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(AppSpacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.panel, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
    }

    private var fillColor: Color {
        if let tint {
            return tint.opacity(colorScheme == .dark ? 0.16 : 0.08)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.58)
    }

    private var strokeColor: Color {
        if let tint {
            return tint.opacity(colorScheme == .dark ? 0.20 : 0.10)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.04)
    }
}

extension View {
    func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let name = systemImage { Image(systemName: name).font(AppFontStyle.headline.font) }
            Text(title).appFont(.headline)
            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal)
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    let actionTitle: String?
    var action: (() -> Void)?

    init(systemImage: String, title: String, subtitle: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title).appFont(.headline)
            if let subtitle { Text(subtitle).appFont(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MeasurementType -> Tint
extension MeasurementType {
    var tint: Color {
        switch self {
        case .bloodPressure: return .indigo // use red only when abnormal
        case .bloodGlucose:  return .orange
        case .weight:        return .teal
        case .heartRate:     return .pink
        }
    }
}

extension MeasurementType {
    var tintUIColor: UIColor {
        switch self {
        case .bloodPressure: return .systemIndigo
        case .bloodGlucose:  return .systemOrange
        case .weight:        return .systemTeal
        case .heartRate:     return .systemPink
        }
    }
}

// MARK: - Rounded corners per-edge
struct RoundedCornersShape: Shape {
    var corners: UIRectCorner = .allCorners
    var radius: CGFloat = 16
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCornersShape(corners: corners, radius: radius))
    }
}
