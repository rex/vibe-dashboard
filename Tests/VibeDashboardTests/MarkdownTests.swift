import Testing
@testable import VibeDashboard

/// TASK_STATE.md files routinely contain fenced shell blocks and ordered lists, so the
/// pure line parser behind `TaskMarkdownView` has to get them right. These pin the two
/// bugs the renderer was missing — a ``` fence rendered as literal body text (losing all
/// code formatting) and an unbalanced fence corrupting the rest of the doc — plus the
/// ordered-list pass-through and the inline-backtick balance guard. All pure, no views.
private typealias MDBlock = TaskMarkdownView.Block

private func md(_ text: String) -> [MDBlock] {
    TaskMarkdownView.parseBlocks(text).map { $0.1 }
}

@Suite("TaskMarkdownView fenced code blocks")
struct MarkdownFenceTests {

    @Test("lines between ``` fences fold into one verbatim code block")
    func balancedFence() {
        // The bug: with no fenced-block state, each ``` and every command line rendered
        // as literal body text. Now the region between the fences is a single .code block
        // and the surrounding lines parse normally.
        #expect(md("## Setup\n```\nnpm install\nnpm test\n```\ndone") == [
            .h2("Setup"),
            .code(["npm install", "npm test"]),
            .body("done"),
        ])
    }

    @Test("a language tag on the opening fence is ignored; the body is still code")
    func fenceWithLanguage() {
        #expect(md("```bash\necho hi\n```") == [.code(["echo hi"])])
    }

    @Test("indentation inside a fence is preserved verbatim")
    func preservesIndentation() {
        #expect(md("```\n    indented\n\ttabbed\n```") == [.code(["    indented", "\ttabbed"])])
    }

    @Test("blank lines inside a fence survive as blank code lines")
    func blankLinesInsideFence() {
        #expect(md("```\na\n\nb\n```") == [.code(["a", "", "b"])])
    }

    @Test("two separate fenced blocks each fold independently")
    func twoBlocks() {
        #expect(md("```\none\n```\nmid\n```\ntwo\n```") == [
            .code(["one"]),
            .body("mid"),
            .code(["two"]),
        ])
    }

    @Test("an unbalanced (unclosed) fence does not corrupt the lines before it")
    func unbalancedFenceKeepsPrefixIntact() {
        let withFence = md("# Title\n- a task\n```\nloose code")
        let noFence = md("# Title\n- a task")
        // The content BEFORE the lone fence parses identically with or without it —
        // "the rest" is never corrupted.
        #expect(Array(withFence.prefix(2)) == noFence)
        #expect(Array(withFence.prefix(2)) == [.h1("Title"), .bullet("a task")])
        // The fence marker itself never leaks through as literal body text (the old bug)…
        #expect(!withFence.contains(.body("```")))
        // …and the trailing content is captured as a code block, not dropped.
        #expect(withFence.last == .code(["loose code"]))
    }

    @Test("a lone ``` is never rendered as literal body text")
    func loneFenceIsNotLiteralBody() {
        #expect(!md("```").contains(.body("```")))
    }
}

@Suite("TaskMarkdownView ordered lists + inline code")
struct MarkdownListTests {

    @Test("ordered markers (1. / 2) …) pass through as list items")
    func orderedItems() {
        #expect(md("1. first\n2. second") == [.ordered("1.", "first"), .ordered("2.", "second")])
        #expect(md("10) tenth") == [.ordered("10)", "tenth")])
    }

    @Test("a digit is only an ordered marker with a real delimiter + space after it")
    func orderedGuards() {
        #expect(md("1.no space") == [.body("1.no space")])   // no space after the dot
        #expect(md("v1.2 shipped") == [.body("v1.2 shipped")]) // no leading digit
        #expect(md("- bullet") == [.bullet("bullet")])        // a dash bullet stays a bullet
    }

    @Test("inline code styles only balanced backticks; a stray tick renders literally")
    func inlineBalance() {
        #expect(TaskMarkdownView.stylesInlineCode("run `make test` now"))
        #expect(TaskMarkdownView.stylesInlineCode("`x`"))
        #expect(!TaskMarkdownView.stylesInlineCode("no code here"))
        #expect(!TaskMarkdownView.stylesInlineCode("unbalanced `tick"))   // 1 tick → literal
        #expect(!TaskMarkdownView.stylesInlineCode("a `b` c `d"))         // 3 ticks → literal
    }

    @Test("a realistic TASK_STATE snippet: checkboxes then a fenced shell block")
    func realisticSnippet() {
        #expect(md("### Progress\n- [x] wire the scanner\n- [ ] ship the UI\n```sh\nmake validate\n```") == [
            .h3("Progress"),
            .check(true, "wire the scanner"),
            .check(false, "ship the UI"),
            .code(["make validate"]),
        ])
    }
}
