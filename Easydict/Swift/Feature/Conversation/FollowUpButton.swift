//
//  FollowUpButton.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols

/// Inline icon button on AI result cards that starts a follow-up question.
/// The host view sets `clickAction` to put the query window into follow-up
/// mode for the card's service, so the next input continues that answer.
@objc(EDFollowUpButton)
final class FollowUpButton: EZHoverButton {
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

    /// Callback invoked when the user clicks the button.
    @objc var clickAction: (() -> ())?

    // MARK: Private

    private func configure() {
        cornerRadius = 5
        image = NSImage(systemSymbol: .bubbleLeftAndBubbleRight)
        toolTip = String(localized: "conversation.follow_up.button.tooltip")

        clickBlock = { [weak self] _ in
            self?.clickAction?()
        }

        executeOnAppearanceChange { [weak self] _, _ in
            guard let self else { return }
            contentTintColor = isDarkMode ? .ez_imageTintDark() : .ez_imageTintLight()
        }
    }
}
