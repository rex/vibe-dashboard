// WindowChrome.swift — AppKit bridges: window drag region + visual effect.

import SwiftUI
import AppKit

/// Configures the window for the custom toolbar: full-size content (so the
/// traffic lights sit ON the toolbar row, not a separate strip), draggable by
/// background, and the traffic lights vertically centered for our toolbar height.
struct WindowConfigurator: NSViewRepresentable {
    var toolbarHeight: CGFloat = 46

    func makeNSView(context: Context) -> NSView {
        let v = ConfigView()
        v.toolbarHeight = toolbarHeight
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ConfigView: NSView {
        var toolbarHeight: CGFloat = 46

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.titlebarSeparatorStyle = .none
            growTitlebar(w)
        }

        /// A zero-width titlebar accessory of the toolbar's height grows the
        /// titlebar so macOS vertically centers the traffic lights in it — the
        /// non-hacky way to align them with a tall custom toolbar.
        private func growTitlebar(_ w: NSWindow) {
            let ident = NSUserInterfaceItemIdentifier("vibe.titlebar.height")
            guard !w.titlebarAccessoryViewControllers.contains(where: { $0.identifier == ident }) else { return }
            let vc = NSTitlebarAccessoryViewController()
            vc.identifier = ident
            vc.layoutAttribute = .trailing
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.heightAnchor.constraint(equalToConstant: toolbarHeight).isActive = true
            spacer.widthAnchor.constraint(equalToConstant: 0).isActive = true
            vc.view = spacer
            w.addTitlebarAccessoryViewController(vc)
        }
    }
}

/// NSVisualEffectView wrapper for the sanctioned whisper of vibrancy.
struct VisualBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { nsView.material = material }
}
