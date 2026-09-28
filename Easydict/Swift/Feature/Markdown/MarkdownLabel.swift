//
//  MarkdownLabel.swift
//  Easydict
//
//  Created by Lin on 2026/4/30.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit

/// `EZLabel` subclass that renders Markdown source through ``MarkdownRenderer``
/// when `markdownEnabled` is `true`. Falls back to the parent's plain-text
/// pipeline otherwise so non-AI services keep their existing appearance and
/// dark-mode switching keeps working through the inherited appearance hook.
@objc(EDMarkdownLabel)
final class MarkdownLabel: EZLabel {
    // MARK: Internal

    /// Toggles between Markdown rendering and plain-text rendering. Re-applies
    /// the current `text` immediately so the visible state stays consistent.
    @objc var markdownEnabled: Bool = true {
        didSet {
            guard oldValue != markdownEnabled else { return }
            updateDisplayedText()
        }
    }

    override func updateDisplayedText() {
        guard markdownEnabled else {
            super.updateDisplayedText()
            return
        }

        // `text` is `nullable` because EZLabel triggers `updateDisplayedText`
        // from the font / line-spacing setters during super init, before
        // `setText:` has run. Coalesce so an early invocation renders nothing
        // instead of crashing.
        let source = text ?? ""
        guard !source.isEmpty else {
            textStorage?.setAttributedString(NSAttributedString())
            return
        }

        let renderer = MarkdownRenderer(
            baseFont: font ?? .systemFont(ofSize: 14),
            foregroundColor: resolvedForegroundColor,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing
        )
        let attributed = renderer.render(source)
        textStorage?.setAttributedString(attributed)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutCodeCopyButtons()
    }

    // MARK: Private

    /// Copy buttons overlaid on code blocks, reused across re-renders.
    private var codeCopyButtons: [CodeBlockCopyButton] = []

    private var resolvedForegroundColor: NSColor {
        if let textForegroundColor { return textForegroundColor }
        return isDarkMode ? .ez_resultTextDark() : .ez_resultTextLight()
    }

    /// Places one copy button at the top-right corner of each code block,
    /// inside the header strip the renderer reserves above the code.
    private func layoutCodeCopyButtons() {
        var blocks: [(range: NSRange, code: String)] = []
        if markdownEnabled, let textStorage {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            textStorage.enumerateAttribute(.markdownCodeBlock, in: fullRange) { value, range, _ in
                if let code = value as? String, range.length > 0 {
                    blocks.append((range, code))
                }
            }
        }

        while codeCopyButtons.count > blocks.count {
            codeCopyButtons.removeLast().removeFromSuperview()
        }
        while codeCopyButtons.count < blocks.count {
            let button = CodeBlockCopyButton()
            addSubview(button)
            codeCopyButtons.append(button)
        }

        guard let layoutManager, let textContainer, let textStorage else { return }

        let size = CodeBlockCopyButton.size
        let inset = (MarkdownRenderer.codeBlockHeaderHeight - size) / 2
        for (button, block) in zip(codeCopyButtons, blocks) {
            button.code = block.code

            let glyphRange = layoutManager.glyphRange(forCharacterRange: block.range, actualCharacterRange: nil)
            layoutManager.ensureLayout(forGlyphRange: glyphRange)

            let paragraphStyle = textStorage.attribute(
                .paragraphStyle, at: block.range.location, effectiveRange: nil
            ) as? NSParagraphStyle
            var blockRect: NSRect
            if let textBlock = paragraphStyle?.textBlocks.first {
                blockRect = layoutManager.boundsRect(for: textBlock, glyphRange: glyphRange)
            } else {
                blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            }
            blockRect = blockRect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)

            // NSTextView is flipped, so minY is the visual top of the block.
            button.frame = NSRect(
                x: blockRect.maxX - size - inset,
                y: blockRect.minY + inset,
                width: size,
                height: size
            )
        }
    }
}
