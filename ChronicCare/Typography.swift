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

    var font: Font {
        switch self {
        case .largeTitle:
            return .system(.largeTitle, design: .rounded).weight(.bold)
        case .title:
            return .system(.title2, design: .rounded).weight(.semibold)
        case .headline:
            return .system(.headline, design: .rounded).weight(.semibold)
        case .subheadline:
            return .system(.subheadline, design: .rounded).weight(.medium)
        case .body:
            return .system(.body, design: .rounded)
        case .label:
            return .system(.callout, design: .rounded).weight(.semibold)
        case .footnote:
            return .system(.footnote, design: .rounded)
        case .caption:
            return .system(.caption, design: .rounded).weight(.medium)
        }
    }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View {
        font(style.font)
    }
}
