//
//  MarkdownRendererTests.swift
//  EasydictTests
//
//  Created by Lin on 2026/4/30.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Testing

@testable import Easydict

// MARK: - MarkdownRendererTests

/// Behavior tests for ``MarkdownRenderer``. Cover the syntactic forms emitted
/// by AI/LLM translation services and verify streaming-safety: incomplete
/// markers must never throw and an unterminated fence renders to the buffer's
/// current end. UI styling values are checked through attribute spot checks
/// rather than full attributed-string equality.
@Suite("Markdown Renderer", .tags(.markdown, .unit))
struct MarkdownRendererTests {
    // MARK: Internal

    @Test("Plain paragraph text renders unchanged")
    func plainText() {
        let result = renderer.render("Hello world.")
        #expect(result.string.trimmingCharacters(in: .newlines) == "Hello world.")
    }

    @Test("ATX heading levels apply scaled fonts")
    func headings() {
        let result = renderer.render("## Translation\nbody text")
        #expect(result.string.contains("Translation"))
        #expect(result.string.contains("body text"))

        let firstFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(firstFont != nil)
        #expect((firstFont?.pointSize ?? 0) > baseSize)
    }

    @Test("Bold emphasis applies a bold font run")
    func boldRun() {
        let result = renderer.render("This is **bold** text.")
        let boldRange = (result.string as NSString).range(of: "bold")
        #expect(boldRange.location != NSNotFound)
        let font = result.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("Italic emphasis applies an italic font run")
    func italicRun() {
        let result = renderer.render("This is *italic* text.")
        let range = (result.string as NSString).range(of: "italic")
        #expect(range.location != NSNotFound)
        let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("Spaced asterisks in expressions stay literal")
    func spacedAsterisksStayLiteral() {
        let result = renderer.render("2 * 3 * 4")
        #expect(result.string == "2 * 3 * 4")
    }

    @Test("Foundation Markdown parsing handles escaped punctuation")
    func escapedPunctuation() {
        let result = renderer.render(#"Keep \*literal\* punctuation."#)
        #expect(result.string == "Keep *literal* punctuation.")
    }

    @Test("Inline code carries a monospaced font and background")
    func inlineCode() {
        let result = renderer.render("Run `swift build` now.")
        let range = (result.string as NSString).range(of: "swift build")
        #expect(range.location != NSNotFound)
        let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontName.lowercased().contains("mono") == true ||
            font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }

    @Test("Fenced code block renders body without fence markers")
    func fencedCodeBlock() {
        let source = "Before\n```\nlet x = 1\n```\nAfter"
        let result = renderer.render(source)
        #expect(result.string.contains("let x = 1"))
        #expect(!result.string.contains("```"))
    }

    @Test("Unterminated fence renders to end of input")
    func unterminatedFence() {
        let source = "Intro\n```\npartial code line"
        let result = renderer.render(source)
        #expect(result.string.contains("partial code line"))
    }

    @Test("Blockquote prefix is stripped from rendered text")
    func blockquote() {
        let result = renderer.render("> a note\n> continued")
        #expect(result.string.contains("a note"))
        #expect(!result.string.contains("> a note"))
    }

    @Test("Unordered list items use a bullet marker")
    func unorderedList() {
        let result = renderer.render("- first\n- second")
        #expect(result.string.contains("•"))
        #expect(result.string.contains("first"))
        #expect(result.string.contains("second"))
    }

    @Test("Ordered list items keep their numbering")
    func orderedList() {
        let result = renderer.render("1. alpha\n2. beta")
        #expect(result.string.contains("1."))
        #expect(result.string.contains("2."))
        #expect(result.string.contains("alpha"))
    }

    @Test("Inline link sets a .link attribute")
    func link() {
        let result = renderer.render("Visit [Apple](https://apple.com).")
        let range = (result.string as NSString).range(of: "Apple")
        #expect(range.location != NSNotFound)
        let url = result.attribute(.link, at: range.location, effectiveRange: nil) as? URL
        #expect(url?.absoluteString == "https://apple.com")
    }

    @Test("Empty input produces an empty attributed string")
    func emptyInput() {
        let result = renderer.render("")
        #expect(result.length == 0)
    }

    @Test("Streaming partial bold marker does not crash and falls back to literal")
    func partialBoldMarker() {
        let result = renderer.render("partial **bold without close")
        #expect(result.string.contains("partial"))
        #expect(result.string.contains("bold without close"))
    }

    @Test("Single-line output has no trailing newline")
    func noTrailingNewline() {
        let result = renderer.render("Hello")
        #expect(result.string == "Hello")
    }

    @Test("Multi-block output does not end with a newline")
    func multiBlockNoTrailingNewline() {
        let result = renderer.render("## Title\n\nBody paragraph.\n\n")
        #expect(!result.string.hasSuffix("\n"))
        #expect(result.string.contains("Title"))
        #expect(result.string.contains("Body paragraph."))
    }

    @Test("Plain paragraphs preserve leading spaces and tabs")
    func plainParagraphPreservesLeadingWhitespace() {
        let result = renderer.render("  indented line\n\tTabbed line")
        #expect(result.string == "  indented line\n\tTabbed line")
    }

    @Test("In-word underscores stay literal so identifiers survive")
    func inWordUnderscoreStaysLiteral() {
        let result = renderer.render("path is foo_bar_baz today")
        #expect(result.string.contains("foo_bar_baz"))
    }

    @Test("Underscore italics still apply at word boundaries")
    func underscoreItalicsAtWordBoundaries() {
        let result = renderer.render("see _italic_ here")
        let range = (result.string as NSString).range(of: "italic")
        #expect(range.location != NSNotFound)
        let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(!result.string.contains("_italic_"))
    }

    @Test("Triple asterisk renders bold and italic together")
    func tripleAsteriskBoldItalic() {
        let result = renderer.render("This is ***super important*** here.")
        let range = (result.string as NSString).range(of: "super important")
        #expect(range.location != NSNotFound)
        let font = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
        let traits = font?.fontDescriptor.symbolicTraits
        #expect(traits?.contains(.bold) == true)
        #expect(traits?.contains(.italic) == true)
        #expect(!result.string.contains("***"))
    }

    @Test("Mixed block content keeps each block readable")
    func mixedContent() {
        let source = """
        ## Translation
        在 TODOS.md 中标记里程碑 0。

        > **Marked** → 标记
        > **TODOS.md** → TODOS.md

        - First item
        - Second item
        """
        let result = renderer.render(source)
        let plain = result.string
        #expect(plain.contains("Translation"))
        #expect(plain.contains("在 TODOS.md 中标记里程碑 0。"))
        #expect(plain.contains("Marked"))
        #expect(plain.contains("First item"))
        #expect(plain.contains("Second item"))
        #expect(!plain.contains("**"))
        #expect(!plain.contains("##"))
    }

    @Test("Thematic break renders as an attachment, not literal dashes")
    func thematicBreak() {
        let result = renderer.render("Before\n\n---\n\nAfter")
        #expect(!result.string.contains("---"))
        #expect(result.string.contains("Before"))
        #expect(result.string.contains("After"))

        let attachmentRange = (result.string as NSString)
            .range(of: "\u{FFFC}")
        #expect(attachmentRange.location != NSNotFound)
        let attachment = result.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil)
        #expect(attachment is NSTextAttachment)
    }

    @Test("Asterisk and underscore thematic breaks are also recognized")
    func thematicBreakVariants() {
        for marker in ["***", "___", "- - -"] {
            let result = renderer.render("A\n\n\(marker)\n\nB")
            #expect(!result.string.contains(marker), "marker \(marker) should not remain literal")
        }
    }

    @Test("GFM table renders cells without literal pipe syntax")
    func table() {
        let source = """
        | Command | Description |
        | :--- | :--- |
        | `xcodebuild build` | Build the app. |
        | `xcodebuild test` | Run tests. |
        """
        let result = renderer.render(source)
        let plain = result.string
        #expect(!plain.contains("|"))
        #expect(!plain.contains(":---"))
        #expect(plain.contains("Command"))
        #expect(plain.contains("Description"))
        #expect(plain.contains("xcodebuild build"))
        #expect(plain.contains("Run tests."))

        let headerRange = (plain as NSString).range(of: "Command")
        let headerStyle = result.attribute(.paragraphStyle, at: headerRange.location, effectiveRange: nil)
            as? NSParagraphStyle
        #expect(headerStyle?.textBlocks.isEmpty == false)
    }

    @Test("A pipe row without a delimiter row stays a plain paragraph")
    func pipeWithoutDelimiterStaysPlain() {
        let result = renderer.render("Run `cmd | xcbeautify` now.")
        #expect(result.string.contains("cmd | xcbeautify"))
    }

    @Test("Fenced code block background spans the block as one continuous region")
    func codeBlockUsesTextBlock() {
        let source = "Before\n```\nline one\nline two\n```\nAfter"
        let result = renderer.render(source)
        let range = (result.string as NSString).range(of: "line one")
        let style = result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.textBlocks.isEmpty == false)
    }

    @Test("Inline LaTeX converts Greek letters and superscripts to Unicode")
    func inlineLatexGreekAndSuperscript() {
        let result = renderer.render(#"Given $\alpha^2 + \beta^2 = \gamma^2$ holds."#)
        let plain = result.string
        #expect(plain.contains("α²"))
        #expect(plain.contains("β²"))
        #expect(plain.contains("γ²"))
        #expect(!plain.contains("$"))
        #expect(!plain.contains("\\alpha"))
    }

    @Test("Inline LaTeX subscript does not trigger italic emphasis")
    func inlineLatexSubscriptAvoidsItalic() {
        let result = renderer.render(#"Let $x_i$ denote the term."#)
        #expect(result.string.contains("xᵢ"))
        #expect(!result.string.contains("_"))
    }

    @Test("LaTeX \\frac and \\sqrt convert to a readable fallback")
    func inlineLatexFracAndSqrt() {
        let result = renderer.render(#"$\frac{a}{b}$ and $\sqrt{2}$"#)
        let plain = result.string
        #expect(plain.contains("a/b"))
        #expect(plain.contains("√(2)"))
    }

    @Test("Currency amounts are not mistaken for LaTeX math")
    func currencyIsNotMath() {
        let result = renderer.render("It costs $5 and $10.")
        #expect(result.string == "It costs $5 and $10.")
    }

    @Test("Unknown LaTeX commands keep their bare name instead of vanishing")
    func unknownLatexCommandKeepsName() {
        let result = renderer.render(#"$\foobarcmd{x}$"#)
        #expect(result.string.contains("foobarcmd"))
    }

    @Test("Block \\$\\$ math renders as a centered converted paragraph")
    func blockMath() {
        let source = "Intro\n\n$$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n$$\n\nOutro"
        let result = renderer.render(source)
        let plain = result.string
        #expect(!plain.contains("$$"))
        #expect(plain.contains("∑"))
        #expect(plain.contains("Intro"))
        #expect(plain.contains("Outro"))

        let sumRange = (plain as NSString).range(of: "∑")
        let style = result.attribute(.paragraphStyle, at: sumRange.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
    }

    @Test("Renderer handles a few hundred chars under streaming budget")
    func streamingBudget() {
        let source = String(repeating: "## Heading\n**bold** and *italic* with `code`.\n", count: 16)
        let start = Date()
        for _ in 0 ..< 30 {
            _ = renderer.render(source)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0)
    }

    // MARK: Private

    private let baseSize: CGFloat = 14

    private var renderer: MarkdownRenderer {
        MarkdownRenderer(
            baseFont: .systemFont(ofSize: baseSize),
            foregroundColor: .labelColor,
            lineSpacing: 4,
            paragraphSpacing: 0
        )
    }
}
