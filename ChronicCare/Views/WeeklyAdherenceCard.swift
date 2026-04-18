import SwiftUI

struct WeeklyAdherenceCard: View {
    @EnvironmentObject var store: DataStore
    var onTap: () -> Void

    private var percent: Double { store.adherencePercent(days: 7) }

    private var tint: Color {
        switch percent {
        case 0.9...: return .green
        case 0.7..<0.9: return .teal
        default: return .orange // no red — tone stays supportive for chronic illness users
        }
    }

    private var headline: String {
        String(format: NSLocalizedString("This week %d%%", comment: "weekly adherence headline"), Int((percent * 100).rounded()))
    }

    private var subline: String {
        switch percent {
        case 0.9...:
            return NSLocalizedString("Great consistency — keep going.", comment: "")
        case 0.7..<0.9:
            return NSLocalizedString("Solid week overall.", comment: "")
        case 0.5..<0.7:
            return NSLocalizedString("A few doses slipped — we'll help you catch up.", comment: "")
        default:
            return NSLocalizedString("Some doses missed. Tap to review and adjust.", comment: "")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.medium) {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.18), lineWidth: 6)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: max(0.02, min(percent, 1.0)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .appFont(.headline)
                        .foregroundStyle(.primary)
                    Text(subline)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(AppSpacing.medium)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(NSLocalizedString("Opens adherence calendar.", comment: ""))
    }
}
