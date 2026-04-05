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
            return Font.system(size: 28, weight: .semibold, design: .rounded)
        case .title:
            return Font.system(size: 24, weight: .semibold, design: .rounded)
        case .headline:
            return Font.system(size: 20, weight: .semibold, design: .rounded)
        case .subheadline:
            return Font.system(size: 18, weight: .medium, design: .rounded)
        case .body:
            return Font.system(size: 18, weight: .regular, design: .rounded)
        case .label:
            return Font.system(size: 17, weight: .medium, design: .rounded)
        case .footnote:
            return Font.system(size: 16, weight: .regular, design: .rounded)
        case .caption:
            return Font.system(size: 14, weight: .regular, design: .rounded)
        }
    }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View {
        font(style.font).dynamicTypeSize(.medium ... .accessibility5)
    }
}
