// ColorPalette.swift — the ONE place raw color literals live.
//
// Ported verbatim from the Vibe Dashboard design system (tokens/colors.css).
// Dark mode ONLY. Views never read this directly — they read `Theme.color.*`.

import SwiftUI

enum ColorPalette {
    // ---- Ink: backgrounds & surfaces (near-black, faintly cool) ----
    static let ink1000 = Color(hex: 0x07090A)   // void — deepest wells, code blocks
    static let ink900  = Color(hex: 0x0A0D0E)   // app background
    static let ink850  = Color(hex: 0x0E1213)   // sunken rows
    static let ink800  = Color(hex: 0x12171A)   // panel / card surface
    static let ink750  = Color(hex: 0x171D20)   // surface-2, table header
    static let ink700  = Color(hex: 0x1D2428)   // raised / hover
    static let ink650  = Color(hex: 0x232B30)   // pressed / active row
    static let ink600  = Color(hex: 0x2C353A)   // strong border, dividers

    // ---- Hairlines ----
    static let lineSoft = Color(hex: 0x161C1F)
    static let line     = Color(hex: 0x202A2E)
    static let lineLoud = Color(hex: 0x2E393F)

    // ---- Foreground: text on ink (green-tinted neutrals) ----
    static let fg50  = Color(hex: 0xF1F6F3)
    static let fg100 = Color(hex: 0xE5ECE8)
    static let fg200 = Color(hex: 0xC5CFCB)
    static let fg300 = Color(hex: 0x97A39E)
    static let fg400 = Color(hex: 0x6B7773)
    static let fg500 = Color(hex: 0x4C5754)
    static let fg600 = Color(hex: 0x353E3B)

    // ---- Brand: acid lime (phosphor) ----
    static let lime200 = Color(hex: 0xE4FFB0)
    static let lime300 = Color(hex: 0xCDFF74)
    static let lime400 = Color(hex: 0xB4FF34)   // PRIMARY ACCENT
    static let lime500 = Color(hex: 0x9BEC1B)
    static let lime600 = Color(hex: 0x7BC60E)
    static let lime700 = Color(hex: 0x5A9209)
    static let limeInk = Color(hex: 0x0B1400)

    // ---- Amber: drift / warning ----
    static let amber300 = Color(hex: 0xFFD479)
    static let amber400 = Color(hex: 0xF7B23C)
    static let amber500 = Color(hex: 0xE2982A)
    static let amber700 = Color(hex: 0x8A5A12)
    static let amberInk = Color(hex: 0x1A1000)

    // ---- Red: fail / surprise / destructive ----
    static let red300 = Color(hex: 0xFF8E87)
    static let red400 = Color(hex: 0xFF5B52)
    static let red500 = Color(hex: 0xE63E36)
    static let red700 = Color(hex: 0x8A201B)
    static let redInk = Color(hex: 0x1C0301)

    // ---- Blue: neutral / informational / links ----
    static let blue300 = Color(hex: 0x9CD2F2)
    static let blue400 = Color(hex: 0x6FB7E0)
    static let blue500 = Color(hex: 0x4E98C6)
    static let blue700 = Color(hex: 0x275A78)
    static let blueInk = Color(hex: 0x03131C)

    // ---- Violet: policy / config (sparingly) ----
    static let violet300 = Color(hex: 0xC4B6FF)
    static let violet400 = Color(hex: 0xA593F5)
    static let violet500 = Color(hex: 0x8772E0)

    // Raw RGB for the lime, for glow shadows that need explicit rgba.
    static let limeRGB = (r: 180.0, g: 255.0, b: 52.0)
}
