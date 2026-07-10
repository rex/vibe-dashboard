// Brand.swift — identity primitives: the pulsing vibe▮ mark/logo, per-app
// emblems + wordmarks, the project-type glyph, remote icons.

import SwiftUI

/// Project-type palette (low-chroma, OUTSIDE the status hues).
struct Lang {
    let code: String
    let label: String
    let color: Color
    let icon: String
    var neutral: Bool = false
}

enum Brand {
    static let lang: [String: Lang] = [
        "python-fastmcp": Lang(code: "mcp", label: "FastMCP", color: Color(hex: 0x8C84C4), icon: "plug"),
        "python-fastapi": Lang(code: "py", label: "FastAPI", color: Color(hex: 0x6E93B8), icon: "zap"),
        "python-stdlib": Lang(code: "py", label: "Python", color: Color(hex: 0x6E93B8), icon: "terminal"),
        "ansible-python": Lang(code: "ans", label: "Ansible", color: Color(hex: 0x73A6C4), icon: "server-cog"),
        "swift-apple": Lang(code: "sw", label: "Swift", color: Color(hex: 0xC98A66), icon: "app-window"),
        "react-spa-ts": Lang(code: "ts", label: "React · TS", color: Color(hex: 0x5AA6C9), icon: "atom"),
        "workspace": Lang(code: "ws", label: "Workspace", color: Color(hex: 0x8A938F), icon: "folder-tree", neutral: true),
    ]

    static func langOf(_ stack: String) -> Lang {
        lang[stack] ?? Lang(code: String(stack.prefix(2)), label: stack, color: Color(hex: 0x7E8A86), icon: "file-code-2")
    }

    /// Optional per-repo custom glyphs: map a repo name to a Lucide icon to give it a
    /// distinct emblem in the tree/tables. Empty by default (falls back to the
    /// language glyph); add your own, e.g. ["my-server": "server"].
    static let emblems: [String: String] = [:]
    static func emblem(id: String, stack: String) -> String { emblems[id] ?? langOf(stack).icon }
}

/// The project-type glyph in the tree + tables.
struct LangGlyph: View {
    let stack: String
    var size: CGFloat = 18
    var health: Health? = nil
    var body: some View {
        let l = Brand.langOf(stack)
        let ring = health.map { Theme.color.health($0) } ?? (l.neutral ? Theme.color.borderStrong : l.color.opacity(0.5))
        Text(l.code)
            .font(VibeFont.mono(size * 0.42, .black))
            .foregroundStyle(l.neutral ? Theme.color.textMuted : l.color)
            .frame(width: size, height: size)
            .background(l.neutral ? Theme.color.surface2 : l.color.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(ring, lineWidth: 1))
    }
}

/// Per-app squircle emblem with the live cursor block.
struct AppEmblem: View {
    let emblem: String
    let stack: String
    var size: CGFloat = 44
    var live: Bool = false
    var body: some View {
        let l = Brand.langOf(stack)
        let accent = l.neutral ? Theme.color.textSecondary : l.color
        ZStack(alignment: .bottomTrailing) {
            VibeIcon(emblem, size: size * 0.46, color: accent)
                .frame(width: size, height: size)
                .background(
                    LinearGradient(colors: [l.color.opacity(l.neutral ? 0 : 0.22), ColorPalette.ink850],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                    .strokeBorder(l.neutral ? Theme.color.borderStrong : l.color.opacity(0.42), lineWidth: 1))
            if live {
                CursorBlink(width: Swift.max(2.5, size * 0.075), height: Swift.max(6, size * 0.2))
                    .padding(size * 0.15)
            }
        }
    }
}

/// App wordmark lockup: emblem + name + tagline.
struct AppWordmark: View {
    let name: String
    let desc: String
    let stack: String
    var emblem: String? = nil
    var live: Bool = false
    var size: CGFloat = 44
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            AppEmblem(emblem: emblem ?? Brand.langOf(stack).icon, stack: stack, size: size, live: live)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(VibeFont.mono(VibeFont.size.lg, .semibold))
                    .foregroundStyle(Theme.color.textBright)
                    .lineLimit(1)
                Text(desc)
                    .font(VibeFont.sans(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
            }
        }
    }
}

/// The Vibe app mark — breathing squircle tile with the lime cursor.
struct VibeMark: View {
    var size: CGFloat = 40
    var live: Bool = true
    var body: some View {
        CursorBlink(width: size * 0.17, height: size * 0.5)
            .frame(width: size, height: size)
            .background(
                RadialGradient(colors: [Color(hex: 0x13241B), Color(hex: 0x0A0F0C), Color(hex: 0x07090A)],
                               center: UnitPoint(x: 0.3, y: 0.18), startRadius: 0, endRadius: size * 0.9)
            )
            .clipShape(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .strokeBorder(Theme.color.okLine, lineWidth: 1))
            .shadow(color: ColorPalette.lime400.opacity(live ? 0.22 : 0), radius: live ? 12 : 0)
    }
}

/// The pulsing terminal wordmark.
struct VibeLogo: View {
    var size: CGFloat = 56
    var sub: String? = "mission control"
    var prompt: Bool = true
    var mark: Bool = false
    var body: some View {
        HStack(spacing: size * 0.32) {
            if mark { VibeMark(size: size * 1.18) }
            VStack(alignment: .leading, spacing: Swift.max(2, size * 0.1)) {
                HStack(spacing: size * 0.16) {
                    if prompt {
                        Text("❯").font(VibeFont.mono(size, .bold)).foregroundStyle(Theme.color.accent.opacity(0.85))
                    }
                    HStack(spacing: size * 0.08) {
                        Text("vibe")
                            .font(VibeFont.mono(size, .black))
                            .tracking(size * -0.04)
                            .foregroundStyle(Theme.color.textBright)
                        CursorBlink(width: size * 0.34, height: size * 0.8)
                    }
                }
                if let sub {
                    Text(sub)
                        .font(VibeFont.mono(Swift.max(9, size * 0.2)))
                        .tracking(Swift.max(9, size * 0.2) * VibeFont.track.wide)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.color.textMuted)
                }
            }
        }
    }
}

/// Compact inline wordmark (mac-parts Wordmark).
struct Wordmark: View {
    var size: CGFloat = 18
    var sub: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
            HStack(spacing: 1) {
                Text("vibe").font(VibeFont.mono(size, .black)).tracking(size * -0.03).foregroundStyle(Theme.color.textBright)
                CursorBlink(width: size * 0.32, height: size * 0.8)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
            }
            if let sub {
                Text(sub).font(VibeFont.mono(size * 0.5)).tracking(size * 0.5 * VibeFont.track.wide)
                    .textCase(.uppercase).foregroundStyle(Theme.color.textMuted)
            }
        }
    }
}

/// Git remote host icon (GitHub / Gitea).
struct RemoteIcon: View {
    let host: String
    var size: CGFloat = 14
    var body: some View {
        switch host {
        case "github": VibeIcon("github", size: size, color: Theme.color.textSecondary)
        case "gitea": VibeIcon("coffee", size: size, color: Color(hex: 0x7BB661))
        default: VibeIcon("git-branch", size: size, color: Theme.color.textMuted)
        }
    }
}
