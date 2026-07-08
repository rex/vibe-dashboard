// RepoIdentityMarks.swift — glanceable per-repo identity marks shown on BOTH fleet
// rows and the repo Overview header: remote-host chips (GitHub / Gitea / other), a CI
// chip, the `RepoBadges` cluster, and `RepoLogoThumb` (the repo's own resolved icon,
// with an honest emblem fallback). Real signals only — nothing renders unless it is
// actually present on the repo.

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// A simplified GitHub octocat silhouette — round head, two ears, three little legs.
/// Enough to read as the GitHub mark at chip size, monochrome, in the mono aesthetic.
struct GitHubCat: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, ox = rect.minX, oy = rect.minY
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * w, y: oy + y * h) }
        var p = Path()
        // ears
        p.move(to: pt(0.20, 0.34)); p.addLine(to: pt(0.30, 0.05)); p.addLine(to: pt(0.46, 0.26)); p.closeSubpath()
        p.move(to: pt(0.80, 0.34)); p.addLine(to: pt(0.70, 0.05)); p.addLine(to: pt(0.54, 0.26)); p.closeSubpath()
        // head / body
        p.addEllipse(in: CGRect(x: ox + 0.15 * w, y: oy + 0.22 * h, width: 0.70 * w, height: 0.60 * h))
        // legs
        for lx in [0.26, 0.455, 0.65] as [CGFloat] {
            p.addRoundedRect(in: CGRect(x: ox + lx * w, y: oy + 0.78 * h, width: 0.09 * w, height: 0.17 * h),
                             cornerSize: CGSize(width: 0.02 * w, height: 0.02 * w))
        }
        return p
    }
}

/// A git remote's host, as a glanceable chip. GitHub → the drawn cat; Gitea → a
/// green teacup; anything else → a neutral branch glyph. Multi-remote repos render
/// one chip PER DISTINCT host (see `RepoBadges`), so an owned gitea mirror alongside
/// a github origin is visible at a glance.
struct RemoteHostMark: View {
    let host: String       // "github" | "gitea" | other
    var size: CGFloat = 18
    private var corner: CGFloat { size * 0.28 }
    private var giteaGreen: Color { Color(hex: 0x7BB661) }   // brand identity hue (matches RemoteIcon)

    var body: some View {
        inner
            .frame(width: size, height: size)
            .background(host == "gitea" ? giteaGreen.opacity(0.12) : Theme.color.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.color.border, lineWidth: 1))
            .help(label)
    }

    @ViewBuilder private var inner: some View {
        switch host {
        case "github": GitHubCat().fill(Theme.color.textBright).frame(width: size * 0.60, height: size * 0.60)
        case "gitea":  VibeIcon("coffee", size: size * 0.60, color: giteaGreen)
        default:       VibeIcon("git-branch", size: size * 0.56, color: Theme.color.textMuted)
        }
    }
    private var label: String {
        switch host {
        case "github": return "GitHub remote"
        case "gitea": return "Gitea remote"
        default: return "\(host) remote"
        }
    }
}

/// CI-configured chip — a workflow exists in `.github`/`.gitea`. One glyph, tooltipped
/// with the provider so github-actions vs gitea-actions is on-hover glanceable.
struct CIBadge: View {
    var provider: String = "ci"
    var size: CGFloat = 18
    private var corner: CGFloat { size * 0.28 }
    var body: some View {
        VibeIcon("zap", size: size * 0.56, color: Theme.color.info)
            .frame(width: size, height: size)
            .background(Theme.color.infoSurfaceSoft)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Theme.color.infoLine, lineWidth: 1))
            .help("CI configured · \(provider)")
    }
}

/// The glanceable identity cluster shown on BOTH fleet rows and the repo Overview
/// header: an optional stack glyph, one mark PER DISTINCT remote host, and a CI chip
/// when a workflow is configured.
struct RepoBadges: View {
    let repo: Repo
    var size: CGFloat = 18
    var showStack: Bool = false

    private var hosts: [String] {
        var seen = Set<String>(); var out: [String] = []
        for r in repo.scm.remotes where !seen.contains(r.host) { seen.insert(r.host); out.append(r.host) }
        return out
    }
    var body: some View {
        HStack(spacing: Theme.space.x1_5) {
            if showStack { LangGlyph(stack: repo.stack, size: size) }
            ForEach(hosts, id: \.self) { RemoteHostMark(host: $0, size: size) }
            if repo.ci.configured { CIBadge(provider: repo.ci.provider, size: size) }
        }
    }
}

/// A repo's OWN icon (app icon / favicon / logo, resolved off-main by `AssetProbe`),
/// shown as a small rounded thumbnail. Falls back to the stack emblem whenever no
/// real icon exists on disk — an honest placeholder, never a mismatched logo.
struct RepoLogoThumb: View {
    let repo: Repo
    var size: CGFloat = 44
    /// Live-session marker gate. OFF by default so repeated fleet rows never spin up a
    /// per-row timer (the emblem's live cursor is a periodic TimelineView); the single
    /// repo header opts in with `live: repo.agentActive`. When ON, `liveState` splits it:
    /// ACTIVE earns the lime cursor, IDLE only a muted amber dot — never bright-live.
    var live: Bool = false
    private var corner: CGFloat { size * 0.235 }
    // Only surface liveness when the caller opts in AND the repo actually has a live
    // session; then the session's own state (active <15m / idle 15–60m) drives the mark.
    private var liveState: AgentState? { live ? repo.agent?.state : nil }
    #if canImport(AppKit)
    @State private var image: NSImage?
    #endif

    var body: some View {
        Group {
            #if canImport(AppKit)
            if let image {
                Image(nsImage: image)
                    .resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Theme.color.border, lineWidth: 1))
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .overlay(alignment: .bottomTrailing) { idleMark }
        #if canImport(AppKit)
        .task(id: repo.absolutePath) {
            let data = await RepoIconCache.shared.thumbnailData(forRepoDir: repo.absolutePath)
            image = data.flatMap(NSImage.init(data:))
        }
        #endif
    }

    private var fallback: some View {
        // ACTIVE lights the emblem's lime cursor; IDLE gets no cursor (the amber dot
        // below stands in) so a quiet session is never dressed up as bright-live.
        AppEmblem(emblem: repo.emblem, stack: repo.stack, size: size, live: liveState == .active)
    }

    /// An IDLE live session (15–60m quiet), marked with a muted amber dot on both the
    /// real-icon and fallback-emblem thumbnails — honestly present, but visibly NOT the
    /// lime "live" cursor that only `.active` earns. Static (no timer) — fleet-row safe.
    @ViewBuilder private var idleMark: some View {
        if liveState == .idle {
            Circle()
                .fill(Theme.color.warn)
                .frame(width: Swift.max(5, size * 0.16), height: Swift.max(5, size * 0.16))
                .overlay(Circle().strokeBorder(Theme.color.bgApp, lineWidth: Swift.max(1, size * 0.03)))
                .padding(Swift.max(1, size * 0.08))
                .help("idle agent · last write \(repo.agent?.lastActivity ?? "—")")
        }
    }
}
