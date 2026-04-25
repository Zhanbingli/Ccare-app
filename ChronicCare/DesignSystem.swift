import SwiftUI

enum EditorialPalette {
    static let primary = Color(red: 0.165, green: 0.420, blue: 0.486) // #2A6B7C
    static let warning = Color(red: 0.753, green: 0.271, blue: 0.271) // #C04545
    static let background = Color(red: 0.980, green: 0.980, blue: 0.980) // #FAFAFA
    static let surface = Color.white
    static let textPrimary = Color(red: 0.110, green: 0.110, blue: 0.118) // #1C1C1E
    static let textSecondary = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    static let textTertiary = Color(red: 0.631, green: 0.631, blue: 0.667) // #A1A1AA
    static let divider = Color(red: 0.898, green: 0.906, blue: 0.922) // #E5E7EB
    static let success = Color(red: 0.180, green: 0.490, blue: 0.310)
}

enum EditorialSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

enum AppSpacing {
    static let micro: CGFloat = 2
    static let xxSmall: CGFloat = 4
    static let tiny: CGFloat = 6
    static let xSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 20
    static let xLarge: CGFloat = 24
}

enum AppRadius {
    static let pill: CGFloat = 8
    static let small: CGFloat = 10
    static let medium: CGFloat = 12
    static let panel: CGFloat = 16
    static let card: CGFloat = 24
    static let hero: CGFloat = 28
}

enum AppSemanticColor {
    static let info = EditorialPalette.primary
    static let success = EditorialPalette.success
    static let warning = EditorialPalette.warning
    static let danger = EditorialPalette.warning
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(EditorialSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EditorialPalette.surface)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(EditorialPalette.divider.opacity(0.65), lineWidth: 0.8)
            )
    }
}

/// Reserved for emphasis states (overdue dose, low supply, critical alert).
/// Don't use as a default container — plain `Card` is the baseline now.
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
            .padding(EditorialSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(EditorialPalette.surface)
                    .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(colorScheme == .dark ? 0.42 : 0.24), lineWidth: 0.9)
            )
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

// MARK: - FlowLayout

/// A layout that wraps children to the next line when horizontal space runs out.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
