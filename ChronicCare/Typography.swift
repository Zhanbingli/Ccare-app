import SwiftUI

enum AppFontStyle {
    case largeTitle
    case title
    case headline
    case subheadline
    case body
    case label
    case footnote
    case caption

    fileprivate func font(design: Font.Design) -> Font {
        switch self {
        case .largeTitle:
            return .system(.largeTitle, design: design).weight(.bold)
        case .title:
            return .system(.title2, design: design).weight(.semibold)
        case .headline:
            return .system(.headline, design: design).weight(.semibold)
        case .subheadline:
            return .system(.subheadline, design: design).weight(.medium)
        case .body:
            return .system(.body, design: design)
        case .label:
            return .system(.callout, design: design).weight(.semibold)
        case .footnote:
            return .system(.footnote, design: design)
        case .caption:
            return .system(.caption, design: design).weight(.medium)
        }
    }

    /// Text styles use the system default design. Rounded is reserved for
    /// numeric values (see `appFontNumeric`) so it reads as emphasis, not noise.
    var font: Font { font(design: .default) }
}

extension View {
    /// Standard text styling — default design.
    func appFont(_ style: AppFontStyle) -> some View {
        font(style.font)
    }

    /// Numeric styling for data values (BP, dose, percent, streaks).
    /// Rounded + monospacedDigit gives the precise, medical feel without
    /// jitter as values change.
    func appFontNumeric(_ style: AppFontStyle) -> some View {
        font(style.font(design: .rounded)).monospacedDigit()
    }
}
