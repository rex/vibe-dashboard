// ColorHex.swift — hex-literal Color initializer + alpha helper.

import SwiftUI

extension Color {
    /// Initialize a Color from a 24-bit RGB or 32-bit ARGB hex literal.
    ///   Color(hex: 0x0A0D0E)          // RGB
    ///   Color(hex: 0xFF0A0D0E)        // ARGB
    public init(hex: UInt32, alpha: Double = 1.0) {
        let hasAlpha = hex > 0xFFFFFF
        let a = hasAlpha ? Double((hex >> 24) & 0xFF) / 255.0 : alpha
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >>  8) & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
