// Icons.swift — Lucide → SF Symbol bridge.
//
// The design kit names icons by Lucide id. Native renders SF Symbols. This
// maps every glyph the kit uses (plus common neighbours) to its closest SF
// Symbol, and exposes `VibeIcon` — the single icon primitive every view uses.

import SwiftUI

enum Lucide {
    /// Lucide id → SF Symbol name. Unknown ids fall back to a dotted circle.
    static let map: [String: String] = [
        // structural / actions
        "refresh-cw": "arrow.clockwise", "rotate-cw": "arrow.clockwise",
        "search": "magnifyingglass", "terminal": "terminal",
        "square-terminal": "terminal", "play": "play.fill", "pause": "pause.fill",
        "plus": "plus", "x": "xmark", "minus": "minus", "check": "checkmark",
        "arrow-right": "arrow.right", "arrow-left": "arrow.left",
        "arrow-up-right": "arrow.up.right", "chevron-right": "chevron.right",
        "chevron-left": "chevron.left", "chevron-down": "chevron.down",
        "chevron-up": "chevron.up", "more-horizontal": "ellipsis",
        "external-link": "arrow.up.right.square", "clipboard": "doc.on.clipboard",
        "copy": "doc.on.doc", "trash-2": "trash", "trash": "trash",
        "settings": "slider.horizontal.3", "sliders": "slider.horizontal.3",
        "sliders-horizontal": "slider.horizontal.3",
        // git / scm
        "git-branch": "arrow.triangle.branch", "git-merge": "arrow.triangle.merge",
        "git-commit-horizontal": "smallcircle.filled.circle",
        "git-pull-request": "arrow.triangle.pull", "git-fork": "arrow.triangle.branch",
        "folder-git-2": "folder.badge.gearshape", "github": "chevron.left.forwardslash.chevron.right",
        "coffee": "cup.and.saucer", "gitea": "cup.and.saucer",
        // status / signal
        "shield-check": "checkmark.shield", "shield": "shield", "shield-alert": "exclamationmark.shield",
        "activity": "waveform.path.ecg", "file-warning": "exclamationmark.triangle",
        "triangle-alert": "exclamationmark.triangle", "alert-triangle": "exclamationmark.triangle",
        "alert-circle": "exclamationmark.circle", "info": "info.circle",
        "check-circle": "checkmark.circle", "check-circle-2": "checkmark.circle.fill",
        "x-circle": "xmark.circle", "circle-check": "checkmark.circle",
        "circle": "circle", "circle-dot": "smallcircle.filled.circle",
        "zap": "bolt.fill", "zap-off": "bolt.slash", "flame": "flame.fill",
        "clock": "clock", "history": "clock.arrow.circlepath", "timer": "timer",
        // agent / mcp / tools
        "bot": "cpu", "cpu": "cpu", "brain": "brain", "waypoints": "point.3.connected.trianglepath.dotted",
        "plug": "powerplug", "plug-zap": "powerplug", "radio": "dot.radiowaves.left.and.right",
        "globe": "globe", "network": "network", "wifi-off": "wifi.slash",
        "mouse-pointer-2": "cursorarrow", "code": "chevron.left.forwardslash.chevron.right",
        "code-2": "chevron.left.forwardslash.chevron.right", "file-code-2": "curlybraces",
        "square-code": "curlybraces.square",
        // files / docs / structure
        "folder": "folder", "folder-tree": "folder", "folder-search": "folder.badge.questionmark",
        "folder-open": "folder", "file": "doc", "file-text": "doc.text",
        "files": "doc.on.doc", "book": "book", "book-open": "book",
        "layers": "square.stack.3d.up", "layout-dashboard": "square.grid.2x2",
        "list": "list.bullet", "list-checks": "checklist", "table": "tablecells",
        // objects / emblems
        "server": "server.rack", "server-cog": "server.rack", "database": "cylinder.split.1x2",
        "container": "shippingbox", "box": "shippingbox", "package": "shippingbox",
        "app-window": "macwindow", "macwindow": "macwindow", "atom": "atom",
        "eye": "eye", "eye-off": "eye.slash", "castle": "building.columns",
        "bird": "bird", "puzzle": "puzzlepiece.extension", "receipt": "doc.plaintext",
        "ship-wheel": "steeringwheel", "activity-square": "waveform.path.ecg",
        // panels / chrome
        "panel-right": "sidebar.right", "panel-left": "sidebar.left",
        "panel-bottom": "rectangle.bottomthird.inset.filled", "sidebar": "sidebar.left",
        "maximize-2": "arrow.up.left.and.arrow.down.right", "minimize-2": "arrow.down.right.and.arrow.up.left",
        "lock": "lock", "unlock": "lock.open", "key": "key",
        "bell": "bell", "bell-off": "bell.slash", "command": "command",
        "power": "power", "power-off": "power", "sparkles": "sparkles",
        "wrench": "wrench.and.screwdriver", "hammer": "hammer",
        "circle-slash": "circle.slash", "ban": "circle.slash",
        "arrow-up": "arrow.up", "arrow-down": "arrow.down",
        "trending-up": "chart.line.uptrend.xyaxis", "trending-down": "chart.line.downtrend.xyaxis",
        "gauge": "gauge.medium", "scan": "viewfinder", "radar": "dot.radiowaves.left.and.right",
        "hard-drive": "internaldrive", "cpu-2": "cpu",
    ]

    static func symbol(_ lucide: String) -> String {
        if let m = map[lucide] { return m }
        // Already an SF symbol name?
        if lucide.contains(".") { return lucide }
        return "circle.dotted"
    }
}

/// The one icon primitive. Renders an SF Symbol for a Lucide id.
struct VibeIcon: View {
    let name: String
    var size: CGFloat = 16
    var weight: Font.Weight = .regular
    var color: Color? = nil

    init(_ name: String, size: CGFloat = 16, weight: Font.Weight = .regular, color: Color? = nil) {
        self.name = name
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Image(systemName: Lucide.symbol(name))
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color ?? Theme.color.textSecondary)
            .frame(width: size, height: size)
    }
}
