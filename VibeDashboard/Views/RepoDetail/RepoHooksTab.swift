// RepoHooksTab.swift — lifecycle hooks (by source) + MCP servers + served side.
//
// Terse, mono-dominant. Hooks grouped into a VibePanel per source; each row
// pairs an event glyph with its matcher/command and a StatusBadge. The MCP
// panel lists this repo's servers (transport, target, tools, broad flag). If
// the repo also *serves* an MCP capability, a "served side" panel enumerates
// guarded tools and the downstream consumers.

import SwiftUI

struct RepoHooksTab: View {
    let repo: Repo

    // Hooks grouped by source, in a stable canonical order.
    private var hooksBySource: [(src: String, hooks: [Hook])] {
        let order = ["claude", "codex", "git", "cursor"]
        let grouped = Dictionary(grouping: repo.hooks, by: \.src)
        let known = order.compactMap { s -> (String, [Hook])? in
            guard let hs = grouped[s], !hs.isEmpty else { return nil }
            return (s, hs)
        }
        let extras = grouped.keys.filter { !order.contains($0) }.sorted().map { ($0, grouped[$0] ?? []) }
        return (known + extras).map { (src: $0.0, hooks: $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space.x4) {
                Text("Hooks & MCP")
                    .font(VibeFont.sans(VibeFont.size.xxl, .semibold))
                    .tracking(VibeFont.size.xxl * VibeFont.track.snug)
                    .foregroundStyle(Theme.color.textBright)

                hooksSection
                mcpSection
                if let serves = repo.serves { servedPanel(serves) }
            }
            .padding(Theme.space.x5)
        }
    }

    // ---- hooks ----

    @ViewBuilder private var hooksSection: some View {
        if repo.hooks.isEmpty {
            VibePanel(title: "lifecycle hooks", icon: "plug") {
                EmptyState(icon: "circle-slash", tone: .neutral,
                           text: "no lifecycle hooks. no guardrails wired for this repo.")
            }
        } else {
            ForEach(hooksBySource, id: \.src) { group in
                VibePanel(title: "\(group.src) hooks", icon: srcIcon(group.src), flushBody: true) {
                    VStack(spacing: 0) {
                        ForEach(group.hooks) { hook in
                            HookRow(hook: hook)
                        }
                    }
                }
            }
        }
    }

    private func srcIcon(_ src: String) -> String {
        switch src {
        case "claude": return "sparkles"
        case "codex": return "cpu"
        case "git": return "git-branch"
        case "cursor": return "mouse-pointer-2"
        default: return "plug"
        }
    }

    // ---- mcp ----

    @ViewBuilder private var mcpSection: some View {
        VibePanel(title: "mcp servers", icon: "waypoints", flushBody: !repo.mcp.isEmpty) {
            if repo.mcp.isEmpty {
                EmptyState(icon: "circle-slash", tone: .neutral,
                           text: "no .mcp.json. no model-context servers registered.")
            } else {
                VStack(spacing: 0) {
                    ForEach(repo.mcp) { server in
                        McpRow(server: server)
                    }
                }
            }
        }
    }

    // ---- served side ----

    @ViewBuilder private func servedPanel(_ serves: ServesInfo) -> some View {
        VibePanel(title: "served side", icon: "server") {
            VStack(alignment: .leading, spacing: Theme.space.x3) {
                HStack(spacing: Theme.space.x2) {
                    Pill(text: serves.transport, tone: .info, icon: "plug")
                    Text(serves.capability)
                        .font(VibeFont.mono(VibeFont.size.sm))
                        .foregroundStyle(Theme.color.textPrimary)
                        .lineLimit(2)
                }

                if !serves.tools.isEmpty {
                    labeledPills("exposes", serves.tools.map { ($0, VibeTone.neutral) })
                }
                if !serves.guarded.isEmpty {
                    labeledPills("guarded", serves.guarded.map { ($0, VibeTone.danger) })
                }

                if !serves.consumers.isEmpty {
                    Text("consumers").vibeMicroLabel(VibeFont.size.xxs)
                    VStack(spacing: Theme.space.x1_5) {
                        ForEach(serves.consumers) { consumer in
                            ConsumerRow(consumer: consumer)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func labeledPills(_ label: String, _ items: [(String, VibeTone)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            Text(label).vibeMicroLabel(VibeFont.size.xxs)
            FlowPills(items: items)
        }
    }
}

// ---- rows ----

/// One lifecycle-hook line: event · matcher · command · status.
private struct HookRow: View {
    let hook: Hook
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            Text(hook.event)
                .font(VibeFont.mono(VibeFont.size.sm, .bold))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1)
                .fixedSize()

            if let matcher = hook.matcher, !matcher.isEmpty {
                Text(matcher)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
                    .fixedSize()
            }

            Text(hook.command)
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(text: hook.status.rawValue, tone: hook.status.tone, small: true)
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(minHeight: Theme.layout.rowH)
        .padding(.vertical, Theme.space.x1_5)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

/// One MCP-server line: name · transport · target · tool-count · [broad] · status.
private struct McpRow: View {
    let server: McpServer
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            HStack(spacing: Theme.space.x2) {
                Text(server.name)
                    .font(VibeFont.mono(VibeFont.size.sm, .bold))
                    .foregroundStyle(Theme.color.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Pill(text: server.transport, tone: .info)
                Text(server.target)
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Theme.space.x2) {
                Text("\(server.tools.count) tools")
                    .font(VibeFont.mono(VibeFont.size.xxs))
                    .foregroundStyle(Theme.color.textFaint)
                    .fixedSize()
                if server.broad { Pill(text: "broad", tone: .danger, icon: "triangle-alert") }
                StatusBadge(text: server.status.rawValue, tone: server.status.tone, small: true)
            }
        }
        .padding(.horizontal, Theme.space.x4)
        .frame(minHeight: Theme.layout.rowH)
        .padding(.vertical, Theme.space.x1_5)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

/// A downstream consumer of this repo's served capability.
private struct ConsumerRow: View {
    let consumer: Consumer
    private var tone: VibeTone {
        switch consumer.status {
        case "connected", "ok", "active": return .ok
        case "failed", "revoked", "error": return .danger
        case "unused", "idle": return .warn
        default: return .neutral
        }
    }
    var body: some View {
        HStack(spacing: Theme.space.x3) {
            Text(consumer.name)
                .font(VibeFont.mono(VibeFont.size.sm, .medium))
                .foregroundStyle(Theme.color.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Text(consumer.token)
                .font(VibeFont.mono(VibeFont.size.xxs))
                .foregroundStyle(Theme.color.textFaint)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            StatusBadge(text: consumer.status, tone: tone, small: true)
        }
        .padding(.vertical, Theme.space.x1)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.color.borderSubtle).frame(height: 1) }
    }
}

/// A simple wrapping pill row (guarded tools / exposed tools).
private struct FlowPills: View {
    let items: [(String, VibeTone)]
    var body: some View {
        WrapHStack(spacing: Theme.space.x1_5, lineSpacing: Theme.space.x1_5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Pill(text: item.0, tone: item.1)
            }
        }
    }
}

/// Minimal flow layout that wraps its children onto multiple lines.
private struct WrapHStack<Content: View>: View {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    @ViewBuilder var content: () -> Content
    var body: some View {
        WrapLayout(spacing: spacing, lineSpacing: lineSpacing) { content() }
    }
}

private struct WrapLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + lineSpacing; rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + lineSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
