// VibeFont.swift — the two-family type system.
//
// JetBrains Mono is the DEFAULT/structural voice; Space Grotesk is display.
// The vendored static weights register under SPLIT family names (Medium /
// SemiBold / ExtraBold are their own families), so we resolve the exact
// family per weight to avoid silent fallback to Regular.

import SwiftUI

enum VibeFont {

    // Type scale (px) from typography.css.
    enum size {
        static let xxs: CGFloat = 10     // legend ticks, dense micro-meta
        static let xs: CGFloat = 11      // uppercase labels, badges, meta
        static let sm: CGFloat = 12.5    // secondary UI, table cells
        static let base: CGFloat = 14    // default body / UI text
        static let md: CGFloat = 16      // emphasized body, card titles
        static let lg: CGFloat = 20      // sub-headings
        static let xl: CGFloat = 26      // section headings
        static let xxl: CGFloat = 34     // page titles
        static let d3: CGFloat = 46      // display
        static let d4: CGFloat = 62      // hero numerals
        static let d5: CGFloat = 84      // splash
    }

    // Tracking is applied per-call via `.tracking(size * em)`.
    enum track {
        static let tight: CGFloat = -0.03   // big display numerals
        static let snug: CGFloat = -0.02
        static let label: CGFloat = 0.08    // UPPERCASE mono micro-labels
        static let wide: CGFloat = 0.14      // eyebrows / spaced kickers
    }

    // ---- JetBrains Mono (structural / data / labels) ----
    static func mono(_ px: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium:
            return .custom("JetBrains Mono Medium", fixedSize: px)
        case .semibold, .bold, .heavy:
            return .custom("JetBrains Mono", fixedSize: px).weight(.bold)
        case .black:
            return .custom("JetBrains Mono ExtraBold", fixedSize: px)
        default:
            return .custom("JetBrains Mono", fixedSize: px)
        }
    }

    // ---- Space Grotesk (display / headings / prose) ----
    static func sans(_ px: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .medium:
            return .custom("Space Grotesk Medium", fixedSize: px)
        case .semibold:
            return .custom("Space Grotesk SemiBold", fixedSize: px)
        case .bold, .heavy, .black:
            return .custom("Space Grotesk", fixedSize: px).weight(.bold)
        default:
            return .custom("Space Grotesk", fixedSize: px)
        }
    }
}

extension View {
    /// Tracked, uppercased mono micro-label — the signature label treatment.
    func vibeMicroLabel(_ px: CGFloat = VibeFont.size.xs,
                        color: Color = Theme.color.textMuted) -> some View {
        self.font(VibeFont.mono(px, .medium))
            .tracking(px * VibeFont.track.label)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}
