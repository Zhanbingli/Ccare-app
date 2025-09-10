import SwiftUI

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}

struct TintedCard<Content: View>: View {
    let tint: Color
    let content: Content
    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: tint.opacity(0.18), radius: 10, x: 0, y: 6)
    }
}

extension View {
    func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let name = systemImage { Image(systemName: name).font(.headline) }
            Text(title).font(.headline)
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
            Text(title).font(.headline)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center) }
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

// MARK: - Action Tile
struct ActionTile: View {
    let color: Color
    let title: String
    let systemImage: String
    let action: () -> Void
    init(color: Color, title: String, systemImage: String, action: @escaping () -> Void) {
        self.color = color
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(color.opacity(0.18)).frame(width: 48, height: 48)
                    Image(systemName: systemImage).foregroundStyle(color).font(.system(size: 20, weight: .semibold))
                }
                Text(title).font(.footnote).foregroundStyle(.primary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
