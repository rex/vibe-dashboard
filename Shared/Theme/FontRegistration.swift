// FontRegistration.swift — register the vendored TTFs at launch.
//
// The fonts live flat in the app bundle's Resources (xcodegen adds them to
// Copy Bundle Resources). We register every bundled .ttf with CoreText so
// `.custom("JetBrains Mono", …)` resolves. Idempotent; main-actor only.

import Foundation
import CoreText

@MainActor
enum FontRegistration {
    private static var done = false

    static func registerBundledFonts() {
        guard !done else { return }
        done = true

        let names = [
            "JetBrainsMono-Regular", "JetBrainsMono-Medium",
            "JetBrainsMono-Bold", "JetBrainsMono-ExtraBold",
            "SpaceGrotesk-Regular", "SpaceGrotesk-Medium",
            "SpaceGrotesk-SemiBold", "SpaceGrotesk-Bold",
        ]

        var registered = 0
        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                Log.app.error("font missing from bundle: \(name, privacy: .public).ttf")
                continue
            }
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
                registered += 1
            }
            // Already-registered returns false with a benign error — ignored.
        }
        Log.app.info("registered \(registered, privacy: .public) bundled fonts")
    }
}
