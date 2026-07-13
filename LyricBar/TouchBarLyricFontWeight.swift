import AppKit

enum TouchBarLyricFontWeight: String, CaseIterable, Identifiable {
    case ultraLight
    case light
    case regular
    case medium
    case semibold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ultraLight:
            return "매우 얇게"
        case .light:
            return "얇게"
        case .regular:
            return "보통"
        case .medium:
            return "중간"
        case .semibold:
            return "굵게"
        }
    }

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .ultraLight:
            return .ultraLight
        case .light:
            return .light
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        }
    }
}
