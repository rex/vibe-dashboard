// WatchMarkdown.swift — block-aware markdown rendering for transcript prose.
// MarkdownBlocks (Shared/DesignSystem) does the segmentation; these views style
// each block: real fenced code wells, heading scale, lime list markers, quotes.
// Inline markdown (bold/italic/`code`/links) renders inside every block.

import SwiftUI

struct WatchMarkdownView: View {
    let text: String
    let fontSize: Double

    var body: some View {
        let blocks = MarkdownBlocks.parse(text)
        VStack(alignment: .leading, spacing: Theme.space.x2) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                render(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func render(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            prose(text, color: Theme.color.textPrimary)
        case .heading(let level, let text):
            Text(WatchInline.render(text, fontSize: fontSize))
                .font(VibeFont.sans(headingSize(level), .semibold))
                .foregroundStyle(Theme.color.textBright)
                .padding(.top, Theme.space.x1)
                .textSelection(.enabled)
        case .code(let lang, let body):
            codeWell(lang: lang, body: body)
        case .bullets(let items):
            list(items) { _ in "–" }
        case .ordered(let items):
            list(items) { "\($0 + 1)." }
        case .quote(let text):
            HStack(alignment: .top, spacing: Theme.space.x2) {
                RoundedRectangle(cornerRadius: 1).fill(Theme.color.borderStrong).frame(width: 2)
                prose(text, color: Theme.color.textMuted)
            }
        case .table(let raw):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(raw)
                    .font(VibeFont.mono(fontSize * 0.92))
                    .foregroundStyle(Theme.color.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
        case .rule:
            Rectangle().fill(Theme.color.border).frame(height: 1).padding(.vertical, Theme.space.x1)
        }
    }

    private func prose(_ text: String, color: Color) -> some View {
        Text(WatchInline.render(text, fontSize: fontSize))
            .font(VibeFont.mono(fontSize))
            .foregroundStyle(color)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func list(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: Theme.space.x1) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: Theme.space.x2) {
                    Text(marker(idx))
                        .font(VibeFont.mono(fontSize, .medium))
                        .foregroundStyle(Theme.color.accentDim)
                        .monospacedDigit()
                    prose(item, color: Theme.color.textPrimary)
                }
            }
        }
    }

    private func codeWell(lang: String?, body: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang {
                Text(lang)
                    .vibeMicroLabel(8, color: Theme.color.textGhost)
                    .padding(.horizontal, Theme.space.x2).padding(.top, Theme.space.x1_5)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(body)
                    .font(VibeFont.mono(fontSize * 0.94))
                    .foregroundStyle(Theme.color.textSecondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(Theme.space.x2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.color.bgVoid)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius.xs, style: .continuous)
            .strokeBorder(Theme.color.borderSubtle, lineWidth: 1))
    }

    private func headingSize(_ level: Int) -> Double {
        switch level {
        case 1: return fontSize + 5
        case 2: return fontSize + 3
        case 3: return fontSize + 1.5
        default: return fontSize + 0.5
        }
    }
}

/// Inline markdown → AttributedString, preserving whitespace and never throwing —
/// a parse failure just shows the raw text (honest fallback).
enum WatchInline {
    static func render(_ text: String, fontSize: Double) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
        for run in attributed.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                attributed[run.range].font = VibeFont.mono(fontSize * 0.94, .medium)
                attributed[run.range].foregroundColor = Theme.color.accentHover
                attributed[run.range].backgroundColor = Theme.color.surfaceSunken
            }
        }
        return attributed
    }
}
