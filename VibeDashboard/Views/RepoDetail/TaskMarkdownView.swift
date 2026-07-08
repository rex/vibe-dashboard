// TaskMarkdownView.swift — the terse TASK_STATE.md renderer.
//
// Line-based, no dependencies: headings, checkboxes, `-`/`*` bullets, ordered
// (`1.` / `2)`) items, blockquotes, fenced ``` code ``` blocks, body text, and
// inline `code` spans. Everything mono except the top-level `#` heading (Grotesk).
// Extracted from RepoAgentTab so each file stays under the architecture line gate;
// the pure parser (`parseBlocks`) is `internal` so the markdown decisions are
// unit-testable. All values flow through Theme / VibeFont.

import SwiftUI

struct TaskMarkdownView: View {
    let text: String

    /// A parsed line or region. A fenced ``` … ``` region collapses to a single
    /// `.code` block carrying its inner lines verbatim (indentation preserved).
    enum Block: Equatable {
        case h1(String), h2(String), h3(String)
        case check(Bool, String)
        case bullet(String)
        case ordered(String, String)   // marker ("1." / "3)") + content
        case quote(String)
        case code([String])            // fenced block body, verbatim
        case body(String)
        case spacer
    }

    // Parsed regions keyed by their originating line index (stable ForEach identity).
    private var blocks: [(Int, Block)] { Self.parseBlocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space.x1_5) {
            ForEach(blocks, id: \.0) { _, block in
                row(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ---- parse ----

    /// Walk the text line-by-line, folding ``` … ``` fences into `.code` regions and
    /// delegating every other line to `parse`. An UNCLOSED fence degrades honestly:
    /// the lines accumulated after it flush as one code block at EOF, and the lines
    /// BEFORE it keep their normal parse — so a stray ``` never corrupts the rest.
    /// Pure + testable (no IO), actor-agnostic so tests can reach it off the main actor.
    nonisolated static func parseBlocks(_ text: String) -> [(Int, Block)] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [(Int, Block)] = []
        var fenceStart: Int?
        var fenceBody: [String] = []
        for (i, raw) in lines.enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let start = fenceStart {                 // closing fence
                    out.append((start, .code(fenceBody)))
                    fenceStart = nil; fenceBody = []
                } else {                                    // opening fence
                    fenceStart = i; fenceBody = []
                }
                continue
            }
            if fenceStart != nil { fenceBody.append(raw); continue }   // inside a fence → verbatim
            out.append((i, parse(raw)))
        }
        if let start = fenceStart { out.append((start, .code(fenceBody))) }   // unterminated → flush
        return out
    }

    /// Classify a single non-fence line. Ordered markers (`1.` / `2)`) pass through as
    /// list items alongside `-`/`*` bullets and `- [ ]` checkboxes. Pure.
    nonisolated private static func parse(_ raw: String) -> Block {
        let line = raw
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .spacer }
        if line.hasPrefix("### ") { return .h3(String(line.dropFirst(4))) }
        if line.hasPrefix("## ")  { return .h2(String(line.dropFirst(3))) }
        if line.hasPrefix("# ")   { return .h1(String(line.dropFirst(2))) }
        if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return .check(true, String(trimmed.dropFirst(6)))
        }
        if trimmed.hasPrefix("- [ ] ") { return .check(false, String(trimmed.dropFirst(6))) }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") { return .bullet(String(trimmed.dropFirst(2))) }
        if let ol = orderedItem(trimmed) { return .ordered(ol.marker, ol.rest) }
        if trimmed.hasPrefix("> ") { return .quote(String(trimmed.dropFirst(2))) }
        return .body(line)
    }

    /// Split a leading ordered-list marker: `1. text` → ("1.", "text"), `3) text` →
    /// ("3)", "text"). Requires ≥1 digit, a `.`/`)` delimiter, then a space — so prose
    /// like "e.g." or "word) note" is left as body. Pure.
    nonisolated private static func orderedItem(_ s: String) -> (marker: String, rest: String)? {
        var i = s.startIndex
        while i < s.endIndex, s[i].isNumber { i = s.index(after: i) }
        guard i > s.startIndex, i < s.endIndex, s[i] == "." || s[i] == ")" else { return nil }
        let afterSep = s.index(after: i)
        guard afterSep < s.endIndex, s[afterSep] == " " else { return nil }
        return (String(s[s.startIndex...i]), String(s[s.index(after: afterSep)...]))
    }

    // ---- render ----

    @ViewBuilder private func row(for block: Block) -> some View {
        switch block {
        case .h1(let s):
            Text(s)
                .font(VibeFont.sans(VibeFont.size.lg, .semibold))
                .tracking(VibeFont.size.lg * VibeFont.track.snug)
                .foregroundStyle(Theme.color.textBright)
                .padding(.top, Theme.space.x1)
        case .h2(let s):
            Text(s)
                .font(VibeFont.mono(VibeFont.size.md, .bold))
                .foregroundStyle(Theme.color.textPrimary)
                .padding(.top, Theme.space.x1)
        case .h3(let s):
            Text(s.uppercased())
                .font(VibeFont.mono(VibeFont.size.xs, .bold))
                .tracking(VibeFont.size.xs * VibeFont.track.label)
                .foregroundStyle(Theme.color.textSecondary)
        case .check(let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
                VibeIcon(done ? "check-circle-2" : "square-dashed", size: 13,
                         color: done ? Theme.color.ok : Theme.color.textFaint)
                inline(s)
                    .strikethrough(done, color: Theme.color.textGhost)
                    .foregroundStyle(done ? Theme.color.textMuted : Theme.color.textPrimary)
            }
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
                Text("·").font(VibeFont.mono(VibeFont.size.sm, .bold)).foregroundStyle(Theme.color.textFaint)
                inline(s).foregroundStyle(Theme.color.textSecondary)
            }
            .padding(.leading, Theme.space.x1)
        case .ordered(let marker, let s):
            HStack(alignment: .firstTextBaseline, spacing: Theme.space.x2) {
                Text(marker)
                    .font(VibeFont.mono(VibeFont.size.sm, .medium))
                    .foregroundStyle(Theme.color.textFaint)
                    .monospacedDigit()
                inline(s).foregroundStyle(Theme.color.textSecondary)
            }
            .padding(.leading, Theme.space.x1)
        case .quote(let s):
            HStack(spacing: Theme.space.x2_5) {
                Rectangle().fill(Theme.color.accent).frame(width: 2)
                inline(s).foregroundStyle(Theme.color.textMuted)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let lines):
            codeBlock(lines)
        case .body(let s):
            inline(s).foregroundStyle(Theme.color.textSecondary)
        case .spacer:
            Spacer().frame(height: Theme.space.x1)
        }
    }

    /// A fenced code block — verbatim mono lines in the deepest well (`bgVoid`, the
    /// palette's designated code surface). Long lines scroll rather than wrap or clip.
    private func codeBlock(_ lines: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, ln in
                    Text(ln.isEmpty ? " " : ln)          // keep blank lines' height
                        .font(VibeFont.mono(VibeFont.size.xs))
                        .foregroundStyle(Theme.color.textSecondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.vertical, Theme.space.x2)
            .padding(.horizontal, Theme.space.x2_5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.bgVoid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.sm, style: .continuous)
            .strokeBorder(Theme.color.border, lineWidth: 1))
        .padding(.vertical, Theme.space.x0_5)
    }

    // ---- inline `code` spans ----

    /// True iff `s` has at least one balanced pair of backticks to style as code — an
    /// odd (unbalanced) count styles nothing, so a stray backtick can't flip the rest
    /// of the line into code. Pure + testable.
    nonisolated static func stylesInlineCode(_ s: String) -> Bool {
        let ticks = s.reduce(0) { $0 + ($1 == "`" ? 1 : 0) }
        return ticks >= 2 && ticks.isMultiple(of: 2)
    }

    /// Render a line as mono body text, styling backtick-delimited spans as code.
    /// Unbalanced backticks render literally (see `stylesInlineCode`).
    private func inline(_ s: String) -> Text {
        guard Self.stylesInlineCode(s) else {
            return Text(s).font(VibeFont.mono(VibeFont.size.sm))
        }
        var out = Text("")
        var isCode = false
        for segment in s.components(separatedBy: "`") {
            let piece = isCode
                ? Text(segment).font(VibeFont.mono(VibeFont.size.sm, .medium)).foregroundColor(Theme.color.accent)
                : Text(segment).font(VibeFont.mono(VibeFont.size.sm))
            out = out + piece
            isCode.toggle()
        }
        return out
    }
}
