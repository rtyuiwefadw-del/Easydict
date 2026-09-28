//
//  QueryAccessoryView.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import SFSafeSymbols

/// Strip shown at the top of the query input: a chip naming the service being
/// followed up, and thumbnails of attached images with remove buttons. It
/// reports its own height so the input view can grow or collapse around it.
@objc(EDQueryAccessoryView)
final class QueryAccessoryView: NSView {
    // MARK: Lifecycle

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: Internal

    /// Called when the user dismisses the follow-up chip.
    @objc var cancelFollowUpAction: (() -> ())?

    /// Called with the index of the thumbnail the user removes.
    @objc var removeImageAction: ((Int) -> ())?

    /// Service name shown in the follow-up chip; `nil` hides the chip.
    @objc var followUpServiceName: String? {
        didSet { rebuild() }
    }

    /// Attached images shown as thumbnails.
    @objc var images: [NSImage] = [] {
        didSet { rebuild() }
    }

    /// Height the input view should reserve for this strip.
    @objc var preferredHeight: CGFloat {
        if !images.isEmpty {
            return Layout.thumbnailSize + Layout.verticalInset * 2
        }
        return followUpServiceName == nil ? 0 : Layout.chipHeight + Layout.verticalInset * 2
    }

    // MARK: Private

    private enum Layout {
        static let thumbnailSize: CGFloat = 44
        static let chipHeight: CGFloat = 22
        static let verticalInset: CGFloat = 6
        static let horizontalInset: CGFloat = 8
        static let removeButtonSize: CGFloat = 16
    }

    private let stackView = NSStackView()

    private func setup() {
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.horizontalInset),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if let followUpServiceName {
            stackView.addArrangedSubview(makeFollowUpChip(serviceName: followUpServiceName))
        }

        for (index, image) in images.enumerated() {
            stackView.addArrangedSubview(makeThumbnail(image: image, index: index))
        }

        isHidden = preferredHeight == 0
    }

    private func makeFollowUpChip(serviceName: String) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = Layout.chipHeight / 2
        chip.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor

        let label = NSTextField(labelWithString: String(
            format: String(localized: "conversation.follow_up.chip.title"),
            serviceName
        ))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .controlAccentColor
        label.lineBreakMode = .byTruncatingTail

        let closeButton = makeRemoveButton { [weak self] in
            self?.cancelFollowUpAction?()
        }
        closeButton.toolTip = String(localized: "conversation.follow_up.chip.cancel")

        for view in [label, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(view)
        }
        chip.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            chip.heightAnchor.constraint(equalToConstant: Layout.chipHeight),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
        ])
        return chip
    }

    private func makeThumbnail(image: NSImage, index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let removeButton = makeRemoveButton { [weak self] in
            self?.removeImageAction?(index)
        }
        removeButton.toolTip = String(localized: "conversation.image.remove")

        container.addSubview(imageView)
        container.addSubview(removeButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Layout.thumbnailSize),
            container.heightAnchor.constraint(equalToConstant: Layout.thumbnailSize),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            removeButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -1),
        ])
        return container
    }

    private func makeRemoveButton(action: @escaping () -> ()) -> NSButton {
        let button = EZHoverButton()
        button.image = NSImage(systemSymbol: .xmarkCircleFill)
        button.contentTintColor = .secondaryLabelColor
        button.clickBlock = { _ in action() }
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.removeButtonSize),
            button.heightAnchor.constraint(equalToConstant: Layout.removeButtonSize),
        ])
        return button
    }
}
