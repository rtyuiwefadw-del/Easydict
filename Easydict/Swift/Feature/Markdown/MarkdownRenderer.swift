//
//  MarkdownRenderer.swift
//  Easydict
//
//  Created by Lin on 2026/4/30.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Foundation

// MARK: - MarkdownRenderer

/// Lightweight Markdown-to-NSAttributedString converter tuned for AI/LLM
/// translation results. Handles ATX headings, emphasis, blockquotes, ordered
/// and unordered lists, fenced and inline code, links, strikethrough,
/// thematic breaks, GFM pipe tables, and a best-effort LaTeX-to-Unicode
/// conversion for `$...$`/`$$...$$` math. Streaming-safe: partial input
/// never throws and an unterminated code fence or math block is rendered
/// through to the current end of the buffer.
struct MarkdownRenderer {
    // MARK: Internal

    /// Base text style. Block elements scale their fonts and adjust paragraph
    /// styles relative to these values so the renderer blends with the host
    /// label's font-size ratio and dark-mode colors.
    let baseFont: NSFont
    let foregroundColor: NSColor
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat

    /// Renders the given Markdown source to an attributed string, applying
    /// per-block paragraph styles and inline emphasis.
    func render(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        var inFence = false
        var codeBuffer: [String] = []
        var inMathBlock = false
        var mathBuffer: [String] = []
        var blankPending = false
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if inFence {
                if isFenceMarker(line) {
                    appendCodeBlock(codeBuffer.joined(separator: "\n"), to: output)
                    codeBuffer.removeAll()
                    inFence = false
                } else {
                    codeBuffer.append(line)
                }
                index += 1
                continue
            }

            if inMathBlock {
                if isMathBlockMarker(line) {
                    appendMathBlock(mathBuffer.joined(separator: "\n"), to: output)
                    mathBuffer.removeAll()
                    inMathBlock = false
                } else {
                    mathBuffer.append(line)
                }
                index += 1
                continue
            }

            let trimmed = line.trimmingPrefix(while: { $0 == " " || $0 == "\t" })
            let trimmedString = String(trimmed)

            if isFenceMarker(trimmedString) {
                inFence = true
                index += 1
                continue
            }

            if isMathBlockMarker(trimmedString) {
                inMathBlock = true
                index += 1
                continue
            }

            if trimmedString.isEmpty {
                if output.length > 0, !blankPending {
                    output.append(NSAttributedString(string: "\n"))
                    blankPending = true
                }
                index += 1
                continue
            }
            blankPending = false

            // A table needs its header row confirmed by a delimiter row right
            // below it; without that lookahead a lone `| a | b |` line falls
            // through to a plain paragraph, which keeps streaming input safe.
            if index + 1 < lines.count,
               isTableRow(trimmedString),
               isTableDelimiterRow(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                let header = splitTableRow(trimmedString)
                let alignments = tableAlignments(from: lines[index + 1])
                var bodyRows: [[String]] = []
                var cursor = index + 2
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard !candidate.isEmpty, isTableRow(candidate) else { break }
                    bodyRows.append(splitTableRow(candidate))
                    cursor += 1
                }
                appendTable(header: header, alignments: alignments, rows: bodyRows, to: output)
                index = cursor
                continue
            }

            if isThematicBreak(trimmedString) {
                appendThematicBreak(to: output)
                index += 1
                continue
            }

            if let (level, content) = headingComponents(trimmedString) {
                appendHeading(level: level, text: content, to: output)
                index += 1
                continue
            }

            if trimmedString.hasPrefix("> ") || trimmedString == ">" {
                let content = trimmedString == ">"
                    ? ""
                    : String(trimmedString.dropFirst(2))
                appendBlockquote(content, to: output)
                index += 1
                continue
            }

            if let bullet = unorderedItem(trimmedString) {
                appendListItem(marker: "•", content: bullet, to: output)
                index += 1
                continue
            }

            if let (number, content) = orderedItem(trimmedString) {
                appendListItem(marker: "\(number).", content: content, to: output)
                index += 1
                continue
            }

            appendParagraph(line, to: output)
            index += 1
        }

        if inFence, !codeBuffer.isEmpty {
            appendCodeBlock(codeBuffer.joined(separator: "\n"), to: output)
        }
        if inMathBlock, !mathBuffer.isEmpty {
            appendMathBlock(mathBuffer.joined(separator: "\n"), to: output)
        }

        // Each block appends a trailing newline; drop the final one so the
        // measured height matches the plain-text path (no extra blank line).
        trimTrailingNewlines(output)

        return output
    }

    // MARK: Private

    // MARK: LaTeX lookup tables

    private static let latexSuperscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
    ]

    private static let latexSubscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ",
        "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
    ]

    private static let latexSymbolMap: [String: String] = [
        // Greek lowercase
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π", "varpi": "ϖ", "rho": "ρ",
        "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
        "chi": "χ", "psi": "ψ", "omega": "ω",
        // Greek uppercase
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π",
        "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators / relations
        "times": "×", "div": "÷", "pm": "±", "mp": "∓", "cdot": "·", "ast": "∗", "star": "⋆",
        "leq": "≤", "le": "≤", "geq": "≥", "ge": "≥", "neq": "≠", "ne": "≠", "approx": "≈",
        "equiv": "≡", "sim": "∼", "simeq": "≃", "propto": "∝", "cong": "≅", "ll": "≪", "gg": "≫",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "leftrightarrow": "↔",
        "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "mapsto": "↦",
        // Calculus / big operators
        "infty": "∞", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏", "int": "∫",
        "oint": "∮", "iint": "∬",
        // Set theory / logic
        "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆", "supset": "⊃",
        "supseteq": "⊇", "cup": "∪", "cap": "∩", "setminus": "∖", "emptyset": "∅", "varnothing": "∅",
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "lnot": "¬",
        "land": "∧", "wedge": "∧", "lor": "∨", "vee": "∨",
        // Misc
        "cdots": "⋯", "ldots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱",
        "circ": "∘", "perp": "⊥", "parallel": "∥", "angle": "∠", "degree": "°",
        "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        "quad": " ", "qquad": "  ",
    ]

    private var monospaceFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
    }

    private var boldFont: NSFont {
        NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
    }

    private var codeBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.06)
        }
    }

    private var tableBorderColor: NSColor {
        NSColor.separatorColor
    }

    private var tableHeaderBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.05)
        }
    }

    private var quoteBarColor: NSColor {
        NSColor.secondaryLabelColor.withAlphaComponent(0.6)
    }

    private var linkColor: NSColor { .linkColor }

    /// Removes trailing newline characters from the end of the attributed
    /// string in place, preserving the attributes of the remaining content.
    private func trimTrailingNewlines(_ output: NSMutableAttributedString) {
        while output.length > 0,
              (output.string as NSString).hasSuffix("\n") {
            output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
        }
    }

    private func baseAttributes(
        font: NSFont? = nil,
        color: NSColor? = nil,
        paragraph: NSParagraphStyle? = nil
    )
        -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? baseFont,
            .foregroundColor: color ?? foregroundColor,
            .kern: 0.2,
        ]
        attrs[.paragraphStyle] = paragraph ?? defaultParagraph()
        return attrs
    }

    private func defaultParagraph(
        firstLineIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        paragraphSpacingBefore: CGFloat = 0
    )
        -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacingBefore
        style.firstLineHeadIndent = firstLineIndent
        style.headIndent = headIndent
        return style
    }

    private func appendHeading(level: Int, text: String, to output: NSMutableAttributedString) {
        let scales: [CGFloat] = [1.6, 1.4, 1.25, 1.15, 1.08, 1.04]
        let scale = scales[max(0, min(level - 1, scales.count - 1))]
        let size = baseFont.pointSize * scale
        let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let paragraph = defaultParagraph(paragraphSpacingBefore: 4)
        let inline = renderInline(text, base: baseAttributes(font: font, paragraph: paragraph))
        output.append(inline)
        output.append(NSAttributedString(string: "\n", attributes: baseAttributes(paragraph: paragraph)))
    }

    private func appendBlockquote(_ text: String, to output: NSMutableAttributedString) {
        let indent: CGFloat = 14
        let paragraph = defaultParagraph(firstLineIndent: indent, headIndent: indent)
        let italicFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
        var attrs = baseAttributes(font: italicFont, color: NSColor.secondaryLabelColor, paragraph: paragraph)
        attrs[.markdownBlockquote] = true
        let inline = renderInline(text, base: attrs)
        output.append(inline)
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private func appendListItem(marker: String, content: String, to output: NSMutableAttributedString) {
        let markerWidth: CGFloat = marker.count > 2 ? 22 : 16
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.firstLineHeadIndent = 4
        style.headIndent = 4 + markerWidth
        style.tabStops = [NSTextTab(textAlignment: .left, location: 4 + markerWidth)]

        let prefix = "\(marker)\t"
        let attrs = baseAttributes(paragraph: style)
        output.append(NSAttributedString(string: prefix, attributes: attrs))
        output.append(renderInline(content, base: attrs))
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private func appendParagraph(_ text: String, to output: NSMutableAttributedString) {
        let attrs = baseAttributes()
        output.append(renderInline(text, base: attrs))
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private func appendThematicBreak(to output: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacing
        let attrs: [NSAttributedString.Key: Any] = [.paragraphStyle: style]

        let attachment = ThematicBreakAttachment(color: .separatorColor)
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        attachmentString.addAttributes(attrs, range: NSRange(location: 0, length: attachmentString.length))
        output.append(attachmentString)
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    /// Renders code as one continuous boxed region via `NSTextBlock` rather
    /// than a per-run background color, which macOS clips to each wrapped
    /// line's glyph width and leaves a jagged edge on multi-line code.
    private func appendCodeBlock(_ code: String, to output: NSMutableAttributedString) {
        let block = NSTextBlock()
        block.backgroundColor = codeBackground
        block.setWidth(10, type: .absoluteValueType, for: .padding)
        // Without an explicit width a bare NSTextBlock falls back to
        // shrink-to-fit sizing, which degenerates into one character per
        // line under TextKit's line-fragment negotiation. Pin it to the
        // container's full width instead.
        block.setValue(100, type: .percentageValueType, for: .width)

        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(2, lineSpacing - 2)
        style.paragraphSpacingBefore = paragraphSpacing
        style.textBlocks = [block]

        let attrs = baseAttributes(font: monospaceFont, paragraph: style)
        output.append(NSAttributedString(string: code, attributes: attrs))
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    /// Renders a `$$ ... $$` block as one centered paragraph of
    /// LaTeX-converted Unicode text.
    private func appendMathBlock(_ latex: String, to output: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing
        style.paragraphSpacingBefore = paragraphSpacing

        let attrs = baseAttributes(paragraph: style)
        let converted = convertLatexToUnicode(latex)
        output.append(NSAttributedString(string: converted, attributes: attrs))
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    /// Builds a GFM pipe table as an `NSTextTable`: one paragraph per cell,
    /// each tagged with an `NSTextTableBlock` at its (row, column), so macOS
    /// lays out and borders a real grid instead of showing literal `|`s.
    private func appendTable(
        header: [String],
        alignments: [NSTextAlignment],
        rows: [[String]],
        to output: NSMutableAttributedString
    ) {
        let table = NSTextTable()
        table.numberOfColumns = alignments.count
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        appendTableRow(header, alignments: alignments, table: table, row: 0, isHeader: true, to: output)
        for (offset, row) in rows.enumerated() {
            appendTableRow(row, alignments: alignments, table: table, row: offset + 1, isHeader: false, to: output)
        }
    }

    private func appendTableRow(
        _ cells: [String],
        alignments: [NSTextAlignment],
        table: NSTextTable,
        row: Int,
        isHeader: Bool,
        to output: NSMutableAttributedString
    ) {
        for column in 0 ..< alignments.count {
            let text = column < cells.count ? cells[column] : ""
            let block = NSTextTableBlock(
                table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1
            )
            block.setBorderColor(tableBorderColor)
            block.setWidth(1, type: .absoluteValueType, for: .border)
            block.setWidth(6, type: .absoluteValueType, for: .padding)
            block.backgroundColor = isHeader ? tableHeaderBackground : .clear

            let style = NSMutableParagraphStyle()
            style.textBlocks = [block]
            style.alignment = alignments[column]
            style.lineSpacing = lineSpacing

            let attrs = baseAttributes(font: isHeader ? boldFont : baseFont, paragraph: style)
            let cell = NSMutableAttributedString(attributedString: renderInline(text, base: attrs))
            cell.append(NSAttributedString(string: "\n", attributes: attrs))
            output.append(cell)
        }
    }

    /// Splits `$...$`/`$$...$$` math spans out of `text` before handing the
    /// rest to Foundation's Markdown parser, so LaTeX like `$x_i + y_i$`
    /// isn't misread as italic emphasis, then converts each math span with
    /// ``convertLatexToUnicode(_:)``.
    private func renderInline(
        _ text: String,
        base: [NSAttributedString.Key: Any]
    )
        -> NSAttributedString {
        let result = NSMutableAttributedString()
        for segment in splitInlineMath(text) {
            switch segment {
            case let .text(plain):
                result.append(renderMarkdownInline(plain, base: base))
            case let .math(latex):
                result.append(NSAttributedString(string: convertLatexToUnicode(latex), attributes: base))
            }
        }
        return result
    }

    private func renderMarkdownInline(
        _ text: String,
        base: [NSAttributedString.Key: Any]
    )
        -> NSAttributedString {
        do {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
            let parsed = try AttributedString(markdown: text, options: options)
            let result = NSMutableAttributedString()

            for run in parsed.runs {
                var attributes = base
                let intent = run.inlinePresentationIntent
                let currentFont = base[.font] as? NSFont ?? baseFont

                if intent?.contains(.stronglyEmphasized) == true {
                    attributes[.font] = NSFontManager.shared.convert(
                        currentFont,
                        toHaveTrait: .boldFontMask
                    )
                }
                if intent?.contains(.emphasized) == true {
                    let font = attributes[.font] as? NSFont ?? currentFont
                    attributes[.font] = NSFontManager.shared.convert(
                        font,
                        toHaveTrait: .italicFontMask
                    )
                }

                if intent?.contains(.code) == true {
                    attributes[.font] = monospaceFont
                    attributes[.backgroundColor] = codeBackground
                }

                if intent?.contains(.strikethrough) == true {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }

                if let url = run.link {
                    attributes[.link] = url
                    attributes[.foregroundColor] = linkColor
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }

                let segment = String(parsed.characters[run.range])
                result.append(NSAttributedString(string: segment, attributes: attributes))
            }

            return result
        } catch {
            // Foundation's parser is intentionally best-effort for streaming
            // input. If an incomplete sequence cannot be parsed, keep it visible.
            return NSAttributedString(string: text, attributes: base)
        }
    }

    // MARK: Block detection

    private func isFenceMarker(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        return stripped.hasPrefix("```")
    }

    private func isMathBlockMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "$$"
    }

    /// Matches a thematic break: a line made of three or more `-`, `*`, or
    /// `_` characters (optionally space-separated), and nothing else.
    private func isThematicBreak(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private func headingComponents(_ line: String) -> (level: Int, text: String)? {
        var hashCount = 0
        for char in line {
            if char == "#", hashCount < 6 { hashCount += 1 } else { break }
        }
        guard hashCount > 0 else { return nil }
        let afterHashes = line.dropFirst(hashCount)
        guard afterHashes.first == " " else { return nil }
        return (hashCount, String(afterHashes.dropFirst()).trimmingCharacters(in: .whitespaces))
    }

    private func unorderedItem(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let first = line.first!
        guard first == "-" || first == "*" || first == "+" else { return nil }
        guard line.dropFirst().first == " " else { return nil }
        return String(line.dropFirst(2))
    }

    private func orderedItem(_ line: String) -> (number: Int, content: String)? {
        var digitCount = 0
        for char in line {
            if char.isASCII, char.isNumber, digitCount < 9 { digitCount += 1 } else { break }
        }
        guard digitCount > 0 else { return nil }
        let afterDigits = line.dropFirst(digitCount)
        guard afterDigits.first == ".", afterDigits.dropFirst().first == " " else { return nil }
        let number = Int(line.prefix(digitCount)) ?? 1
        return (number, String(afterDigits.dropFirst(2)))
    }

    // MARK: Table detection

    private func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    /// Splits a pipe row into cell strings, dropping one leading and one
    /// trailing `|` if present (GFM tables allow either style).
    private func splitTableRow(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Matches a GFM table delimiter row: cells of only `-`, optionally
    /// bracketed by `:` for alignment, e.g. `:---`, `---:`, `:---:`.
    private func isTableDelimiterRow(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            var inner = cell
            if inner.hasPrefix(":") { inner.removeFirst() }
            if inner.hasSuffix(":") { inner.removeLast() }
            return !inner.isEmpty && inner.allSatisfy { $0 == "-" }
        }
    }

    private func tableAlignments(from delimiterRow: String) -> [NSTextAlignment] {
        splitTableRow(delimiterRow).map { cell in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            if left, right { return .center }
            if right { return .right }
            return .left
        }
    }

    // MARK: LaTeX math

    /// Finds `$...$`/`$$...$$` spans in `text` using Pandoc's heuristic: the
    /// opening `$` must be followed by a non-space character and the closing
    /// `$` must be preceded by a non-space character and not followed by a
    /// digit, so ordinary currency like `$5 and $10` is left untouched.
    private func splitInlineMath(_ text: String) -> [MarkdownInlineSegment] {
        var segments: [MarkdownInlineSegment] = []
        var buffer = ""
        let chars = Array(text)
        var i = 0

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            segments.append(.text(buffer))
            buffer = ""
        }

        while i < chars.count {
            if chars[i] == "$" {
                let isDouble = i + 1 < chars.count && chars[i + 1] == "$"
                let delimiterLength = isDouble ? 2 : 1
                let contentStart = i + delimiterLength

                if contentStart < chars.count, !chars[contentStart].isWhitespace {
                    var j = contentStart
                    var closeIndex: Int?
                    while j < chars.count {
                        let isDollar = chars[j] == "$"
                        let closesDouble = isDouble && j + 1 < chars.count && chars[j + 1] == "$"
                        if isDollar, !isDouble || closesDouble {
                            let precededByNonSpace = j > contentStart && !chars[j - 1].isWhitespace
                            let afterIndex = isDouble ? j + 2 : j + 1
                            let notFollowedByDigit = afterIndex >= chars.count || !chars[afterIndex].isNumber
                            if precededByNonSpace, notFollowedByDigit {
                                closeIndex = j
                                break
                            }
                        }
                        j += 1
                    }
                    if let closeIndex, closeIndex > contentStart {
                        flushBuffer()
                        segments.append(.math(String(chars[contentStart ..< closeIndex])))
                        i = isDouble ? closeIndex + 2 : closeIndex + 1
                        continue
                    }
                }
            }
            buffer.append(chars[i])
            i += 1
        }

        flushBuffer()
        return segments
    }

    /// Converts a best-effort subset of LaTeX math source to Unicode: Greek
    /// letters, common operators/symbols, `\frac`, `\sqrt`, `\text`-family
    /// wrappers, and `^`/`_` super/subscripts. A command with no known
    /// mapping is kept as its bare name so content never silently vanishes.
    private func convertLatexToUnicode(_ source: String) -> String {
        var result = ""
        let chars = Array(source)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            if char == "\\" {
                var j = i + 1
                var name = ""
                while j < chars.count, chars[j].isLetter {
                    name.append(chars[j])
                    j += 1
                }

                guard !name.isEmpty else {
                    // `\{`, `\}`, `\%`, `\\`, etc: an escaped literal symbol.
                    if j < chars.count {
                        result.append(chars[j])
                        i = j + 1
                    } else {
                        i = j
                    }
                    continue
                }

                switch name {
                case "frac":
                    let numStart = skipLatexSpaces(chars, from: j)
                    if let (num, afterNum) = readLatexBraceGroup(chars, from: numStart) {
                        let denStart = skipLatexSpaces(chars, from: afterNum)
                        if let (den, afterDen) = readLatexBraceGroup(chars, from: denStart) {
                            result += convertLatexToUnicode(num) + "/" + convertLatexToUnicode(den)
                            i = afterDen
                            continue
                        }
                    }
                case "sqrt":
                    let bodyStart = skipLatexSpaces(chars, from: j)
                    if let (body, after) = readLatexBraceGroup(chars, from: bodyStart) {
                        result += "√(" + convertLatexToUnicode(body) + ")"
                        i = after
                        continue
                    }
                    result += "√"
                    i = j
                    continue
                case "mathbf", "mathcal", "mathit", "mathrm", "operatorname", "text":
                    let bodyStart = skipLatexSpaces(chars, from: j)
                    if let (body, after) = readLatexBraceGroup(chars, from: bodyStart) {
                        result += convertLatexToUnicode(body)
                        i = after
                        continue
                    }
                case "left", "right":
                    i = j
                    continue
                default:
                    if let symbol = Self.latexSymbolMap[name] {
                        result += symbol
                        i = j
                        continue
                    }
                }

                // Unhandled command: keep its bare name rather than dropping
                // the content the user actually cares about.
                result += name
                i = j
                continue
            }

            if char == "^" || char == "_" {
                let map = char == "^" ? Self.latexSuperscriptMap : Self.latexSubscriptMap
                let next = i + 1
                if next < chars.count, chars[next] == "{" {
                    if let (body, after) = readLatexBraceGroup(chars, from: next) {
                        result += mapLatexCharacters(convertLatexToUnicode(body), using: map)
                        i = after
                        continue
                    }
                } else if next < chars.count {
                    result += mapLatexCharacters(String(chars[next]), using: map)
                    i = next + 1
                    continue
                }
            }

            result.append(char)
            i += 1
        }

        return result
    }

    /// Reads a balanced `{...}` group starting at `start`. Returns the inner
    /// content and the index just past the closing brace, or `nil` if
    /// `start` isn't an opening brace or the group never closes.
    private func readLatexBraceGroup(_ chars: [Character], from start: Int) -> (content: String, next: Int)? {
        guard start < chars.count, chars[start] == "{" else { return nil }
        var depth = 1
        var j = start + 1
        var content = ""
        while j < chars.count, depth > 0 {
            if chars[j] == "{" {
                depth += 1
            } else if chars[j] == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            content.append(chars[j])
            j += 1
        }
        guard depth == 0 else { return nil }
        return (content, j + 1)
    }

    private func skipLatexSpaces(_ chars: [Character], from index: Int) -> Int {
        var i = index
        while i < chars.count, chars[i] == " " { i += 1 }
        return i
    }

    private func mapLatexCharacters(_ text: String, using map: [Character: Character]) -> String {
        String(text.map { map[$0] ?? $0 })
    }
}

// MARK: - MarkdownInlineSegment

/// A `$...$`/`$$...$$` math span, or the plain Markdown text around one.
private enum MarkdownInlineSegment {
    case text(String)
    case math(String)
}

// MARK: - Custom attribute keys

extension NSAttributedString.Key {
    /// Marks a run that originated from a Markdown blockquote block, allowing
    /// host views to draw a side bar without re-parsing the source.
    static let markdownBlockquote = NSAttributedString.Key("EDMarkdownBlockquote")
}

// MARK: - ThematicBreakAttachment

/// `NSTextAttachment` that draws a 1pt horizontal rule spanning the full
/// width of its line fragment, so a `---`/`***`/`___` thematic break renders
/// as a divider instead of literal characters, at whatever width the host
/// view currently lays out at.
private final class ThematicBreakAttachment: NSTextAttachment {
    // MARK: Lifecycle

    init(color: NSColor) {
        self.color = color
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    )
        -> CGRect {
        CGRect(x: 0, y: 0, width: lineFrag.width, height: 1)
    }

    override func image(
        forBounds imageBounds: CGRect,
        textContainer: NSTextContainer?,
        characterIndex charIndex: Int
    )
        -> NSImage? {
        let size = imageBounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        return NSImage(size: size, flipped: false) { [color] rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    // MARK: Private

    private let color: NSColor
}
