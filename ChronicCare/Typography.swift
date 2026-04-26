import SwiftUI

enum AppFontStyle {
    case heroNumber
    case displayTitle
    case largeTitle
    case title
    case headline
    case subheadline
    case body
    case label
    case footnote
    case caption
    case micro

    fileprivate func font(design: Font.Design) -> Font {
        switch self {
        case .heroNumber:
            return .system(size: 48, weight: .bold, design: .rounded)
        case .displayTitle:
            return .system(size: 30, weight: .bold, design: .default)
        case .largeTitle:
            return .system(.largeTitle, design: design).weight(.bold)
        case .title:
            return .system(.title2, design: design).weight(.semibold)
        case .headline:
            return .system(size: 18, weight: .semibold, design: design)
        case .subheadline:
            return .system(size: 16, weight: .medium, design: design)
        case .body:
            return .system(size: 17, weight: .regular, design: design)
        case .label:
            return .system(size: 16, weight: .semibold, design: design)
        case .footnote:
            return .system(size: 14, weight: .regular, design: design)
        case .caption:
            return .system(size: 14, weight: .regular, design: design)
        case .micro:
            return .system(size: 12, weight: .medium, design: design)
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
