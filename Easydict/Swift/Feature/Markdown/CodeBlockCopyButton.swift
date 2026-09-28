//
//  CodeBlockCopyButton.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols

/// Small icon button overlaid on the top-right corner of a rendered Markdown
/// code block. Clicking copies the block's raw code to the pasteboard and
/// briefly swaps the icon to a checkmark as confirmation.
final class CodeBlockCopyButton: EZHoverButton {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    // MARK: Internal

    /// Side length of the square button.
    static let size: CGFloat = 20

    /// Raw code copied when the button is clicked.
    var code = ""

    // MARK: Private

    private var resetIconWorkItem: DispatchWorkItem?

    private func configure() {
        cornerRadius = 4
        image = NSImage(systemSymbol: .docOnDoc)
        toolTip = String(localized: "markdown.code_block.copy.tooltip")

        clickBlock = { [weak self] _ in
            self?.copyCode()
        }

        executeOnAppearanceChange { [weak self] _, _ in
            guard let self else { return }
            contentTintColor = isDarkMode ? .ez_imageTintDark() : .ez_imageTintLight()
        }
    }

    private func copyCode() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)

        image = NSImage(systemSymbol: .checkmark)
        toolTip = String(localized: "markdown.code_block.copy.copied")

        resetIconWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.image = NSImage(systemSymbol: .docOnDoc)
            self?.toolTip = String(localized: "markdown.code_block.copy.tooltip")
        }
        resetIconWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }
}
