// MarkdownBlocks.swift — block-level markdown segmentation for transcript rendering.
//
// `AttributedString(markdown:)` only understands INLINE markdown per run — fed a
// whole assistant message it flattens paragraphs, drops fences, and mangles lists
// (exactly the "markdown isn't respected" complaint). This splits text into block
// structure first; views then render each block (inline markdown within it) with
// real styling. Pure string → value transform, no IO — fully unit-testable.

import Foundation

enum MarkdownBlock: Hashable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    case code(lang: String?, body: String)
    case bullets([String])
    case ordered([String])
    case quote(String)
    case table(String)      // raw table lines — rendered mono so the alignment survives
    case rule
}

enum MarkdownBlocks {
    /// The open prose buffers; at most one collects at a time — starting a different
    /// shape flushes the rest, a blank line flushes everything.
    private struct Accumulator {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []
        var quote: [String] = []
        var table: [String] = []

        enum Buffer { case paragraph, bullets, ordered, quote, table }

        mutating func flush(keeping keep: Buffer? = nil) {
            if keep != .paragraph, !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = []
            }
            if keep != .bullets, !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if keep != .ordered, !ordered.isEmpty { blocks.append(.ordered(ordered)); ordered = [] }
            if keep != .quote, !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n"))); quote = []
            }
            if keep != .table, !table.isEmpty {
                blocks.append(.table(table.joined(separator: "\n"))); table = []
            }
        }
    }

    static func parse(_ text: String) -> [MarkdownBlock] {
        var acc = Accumulator()
        var inCode = false
        var codeLang: String?
        var code: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if inCode {
                if trimmed.hasPrefix("```") {
                    acc.blocks.append(.code(lang: codeLang, body: code.joined(separator: "\n")))
                    code = []; codeLang = nil; inCode = false
                } else {
                    code.append(line)
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                acc.flush()
                let lang = trimmed.drop(while: { $0 == "`" }).trimmingCharacters(in: .whitespaces)
                codeLang = lang.isEmpty ? nil : lang
                inCode = true
                continue
            }
            if trimmed.isEmpty { acc.flush(); continue }
            if let heading = headingOf(trimmed) { acc.flush(); acc.blocks.append(heading); continue }
            if isRule(trimmed) { acc.flush(); acc.blocks.append(.rule); continue }
            if trimmed.hasPrefix(">") {
                acc.flush(keeping: .quote)
                acc.quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if trimmed.hasPrefix("|") {
                acc.flush(keeping: .table)
                acc.table.append(line)
                continue
            }
            if let item = bulletItem(line) {
                acc.flush(keeping: .bullets)
                acc.bullets.append(item)
                continue
            }
            if let item = orderedItem(line) {
                acc.flush(keeping: .ordered)
                acc.ordered.append(item)
                continue
            }
            // An indented follow-on line continues the open list item.
            if !acc.bullets.isEmpty, line.hasPrefix("  ") {
                acc.bullets[acc.bullets.count - 1] += "\n" + trimmed
                continue
            }
            if !acc.ordered.isEmpty, line.hasPrefix("  ") {
                acc.ordered[acc.ordered.count - 1] += "\n" + trimmed
                continue
            }
            acc.flush(keeping: .paragraph)
            acc.paragraph.append(line)
        }
        if inCode {   // unterminated fence — still render what streamed in as code
            acc.blocks.append(.code(lang: codeLang, body: code.joined(separator: "\n")))
        }
        acc.flush()
        return acc.blocks
    }

    static func headingOf(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("#") else { return nil }
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard hashes.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        return .heading(level: hashes.count, text: rest.trimmingCharacters(in: .whitespaces))
    }

    static func isRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" } || trimmed.allSatisfy { $0 == "*" }
            || trimmed.allSatisfy { $0 == "_" }
    }

    static func bulletItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return String(trimmed.dropFirst(marker.count))
        }
        return nil
    }

    static func orderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = trimmed.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
