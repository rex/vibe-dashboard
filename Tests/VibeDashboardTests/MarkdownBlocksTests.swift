// MarkdownBlocksTests.swift — block segmentation the watch window renders from.

import Testing
@testable import VibeDashboard

@Suite("markdown blocks")
struct MarkdownBlocksTests {
    @Test("paragraphs, heading, fenced code with language")
    func basics() throws {
        let blocks = MarkdownBlocks.parse("""
        # Title

        First paragraph
        continues here.

        ```swift
        let x = 1
        ```
        """)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First paragraph\ncontinues here."),
            .code(lang: "swift", body: "let x = 1"),
        ])
    }

    @Test("an unterminated fence still renders as code")
    func unterminatedFence() throws {
        let blocks = MarkdownBlocks.parse("before\n```\nraw stream")
        #expect(blocks == [.paragraph("before"), .code(lang: nil, body: "raw stream")])
    }

    @Test("bullet and ordered lists, with indented continuations")
    func lists() throws {
        let blocks = MarkdownBlocks.parse("""
        - first
        - second
          with a continuation
        1. one
        2) two
        """)
        #expect(blocks == [
            .bullets(["first", "second\nwith a continuation"]),
            .ordered(["one", "two"]),
        ])
    }

    @Test("quotes join, rules split, tables stay raw")
    func quotesRulesTables() throws {
        let blocks = MarkdownBlocks.parse("""
        > wisdom
        > continues

        ---

        | a | b |
        |---|---|
        | 1 | 2 |
        """)
        #expect(blocks == [
            .quote("wisdom\ncontinues"),
            .rule,
            .table("| a | b |\n|---|---|\n| 1 | 2 |"),
        ])
    }

    @Test("code fences ignore markdown-looking content inside")
    func fencesShieldContent() throws {
        let blocks = MarkdownBlocks.parse("```\n# not a heading\n- not a bullet\n```")
        #expect(blocks == [.code(lang: nil, body: "# not a heading\n- not a bullet")])
    }

    @Test("hash without a space is not a heading; 4+ digits are not an ordered item")
    func edgeCases() throws {
        #expect(MarkdownBlocks.headingOf("#hashtag") == nil)
        #expect(MarkdownBlocks.orderedItem("2026. a year") == nil)
        #expect(MarkdownBlocks.bulletItem("-dash") == nil)
    }
}
