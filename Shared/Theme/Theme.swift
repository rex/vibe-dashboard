// Theme.swift — the design-token chokepoint (semantic aliases + scale).
//
// Every view reads Theme.color / Theme.size / Theme.space / Theme.radius /
// Theme.motion. Never a raw ColorPalette member, never a magic number.
// Ported from tokens/{colors,spacing,typography,effects}.css.

import SwiftUI

enum Theme {

    // ---------------------------------------------------------------
    // Semantic color
    // ---------------------------------------------------------------
    enum color {
        // Surfaces
        static let bgApp        = ColorPalette.ink900
        static let bgVoid       = ColorPalette.ink1000
        static let surface1     = ColorPalette.ink800    // default card / panel
        static let surface2     = ColorPalette.ink750    // nested / table header
        static let surfaceSunken = ColorPalette.ink850   // wells, inputs, code
        static let surfaceRaised = ColorPalette.ink700   // hover / popover / dropdown
        static let surfaceActive = ColorPalette.ink650   // pressed / selected row

        // Borders
        static let borderSubtle = ColorPalette.lineSoft
        static let border       = ColorPalette.line
        static let borderStrong = ColorPalette.lineLoud
        static let borderDivider = ColorPalette.ink600

        // Text
        static let textPrimary   = ColorPalette.fg100
        static let textBright    = ColorPalette.fg50
        static let textSecondary = ColorPalette.fg300
        static let textMuted     = ColorPalette.fg400
        static let textFaint     = ColorPalette.fg500
        static let textGhost     = ColorPalette.fg600
        static let textOnAccent  = ColorPalette.limeInk

        // Accent (brand)
        static let accent      = ColorPalette.lime400
        static let accentHover = ColorPalette.lime300
        static let accentPress = ColorPalette.lime500
        static let accentDim   = ColorPalette.lime600

        // Status foreground hue
        static let ok     = ColorPalette.lime400
        static let warn   = ColorPalette.amber400
        static let danger = ColorPalette.red400
        static let info   = ColorPalette.blue400
        static let policy = ColorPalette.violet400

        // Status chip/row backgrounds (low-alpha fills)
        static let okSurface     = ColorPalette.lime400.opacity(0.10)
        static let okSurfaceSoft = ColorPalette.lime400.opacity(0.055)
        static let okLine        = ColorPalette.lime400.opacity(0.30)
        static let warnSurface     = ColorPalette.amber400.opacity(0.12)
        static let warnSurfaceSoft = ColorPalette.amber400.opacity(0.06)
        static let warnLine        = ColorPalette.amber400.opacity(0.32)
        static let dangerSurface     = ColorPalette.red400.opacity(0.12)
        static let dangerSurfaceSoft = ColorPalette.red400.opacity(0.06)
        static let dangerLine        = ColorPalette.red400.opacity(0.34)
        static let infoSurface     = ColorPalette.blue400.opacity(0.12)
        static let infoSurfaceSoft = ColorPalette.blue400.opacity(0.06)
        static let infoLine        = ColorPalette.blue400.opacity(0.30)
        static let violetSurface = ColorPalette.violet400.opacity(0.12)
        static let violetLine    = ColorPalette.violet400.opacity(0.30)

        // Tone → color resolvers.
        static func tone(_ t: VibeTone) -> Color {
            switch t {
            case .ok: return ok
            case .warn: return warn
            case .danger: return danger
            case .info: return info
            case .policy: return policy
            case .neutral: return textSecondary
            }
        }
        static func toneSurface(_ t: VibeTone) -> Color {
            switch t {
            case .ok: return okSurface
            case .warn: return warnSurface
            case .danger: return dangerSurface
            case .info: return infoSurface
            case .policy: return violetSurface
            case .neutral: return surface2
            }
        }
        static func toneLine(_ t: VibeTone) -> Color {
            switch t {
            case .ok: return okLine
            case .warn: return warnLine
            case .danger: return dangerLine
            case .info: return infoLine
            case .policy: return violetLine
            case .neutral: return border
            }
        }
        static func health(_ h: Health) -> Color {
            switch h {
            case .ok: return ok
            case .warn: return warn
            case .danger: return danger
            case .idle: return textFaint
            }
        }
    }

    // ---------------------------------------------------------------
    // Spacing — 4px grid (spacing.css)
    // ---------------------------------------------------------------
    enum space {
        static let px: CGFloat = 1
        static let x0_5: CGFloat = 2
        static let x1: CGFloat = 4
        static let x1_5: CGFloat = 6
        static let x2: CGFloat = 8
        static let x2_5: CGFloat = 10
        static let x3: CGFloat = 12
        static let x4: CGFloat = 16
        static let x5: CGFloat = 20
        static let x6: CGFloat = 24
        static let x7: CGFloat = 28
        static let x8: CGFloat = 32
        static let x10: CGFloat = 40
        static let x12: CGFloat = 48
        static let x16: CGFloat = 64
    }

    // ---------------------------------------------------------------
    // Radius (tight, instrument feel)
    // ---------------------------------------------------------------
    enum radius {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 10
        static let xl: CGFloat = 14
        static let full: CGFloat = 999
    }

    // ---------------------------------------------------------------
    // Border widths
    // ---------------------------------------------------------------
    enum stroke {
        static let hair: CGFloat = 1
        static let thick: CGFloat = 2
    }

    // ---------------------------------------------------------------
    // Layout rails (from spacing.css)
    // ---------------------------------------------------------------
    enum layout {
        static let sidebar: CGFloat = 248
        static let inspector: CGFloat = 340
        static let topbar: CGFloat = 52
        static let rowH: CGFloat = 30       // dense mac row (comfortable)
        static let rowHLg: CGFloat = 52
    }

    // ---------------------------------------------------------------
    // Motion (effects.css) — quick, mechanical, no bounce.
    // ---------------------------------------------------------------
    enum motion {
        static let durInstant: Double = 0.08
        static let durFast: Double = 0.14
        static let durBase: Double = 0.20
        static let durSlow: Double = 0.32
        static let easeOut = Animation.timingCurve(0.2, 0.6, 0.2, 1, duration: durFast)
        static let easeOutBase = Animation.timingCurve(0.2, 0.6, 0.2, 1, duration: durBase)
        static let easeInOut = Animation.timingCurve(0.4, 0, 0.2, 1, duration: durBase)
    }
}
