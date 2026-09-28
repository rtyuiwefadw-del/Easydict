//
//  ChatImageLoader.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// Reads images the user wants to attach to an AI question, either from the
/// pasteboard (copied image files or raw image data such as screenshots) or
/// from an open panel. Text on the pasteboard always wins over image data.
@objc(EDChatImageLoader)
final class ChatImageLoader: NSObject {
    /// Maximum number of images attached to one question.
    @objc static let maxImageCount = 4

    /// Returns images on the pasteboard, or an empty array when it should be
    /// pasted as text. Rich-text sources such as Office also put a rendered
    /// image on the pasteboard, so image data is used only without a string.
    @objc
    static func images(from pasteboard: NSPasteboard) -> [NSImage] {
        let imageFileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [
                .urlReadingFileURLsOnly: true,
                .urlReadingContentsConformToTypes: [UTType.image.identifier],
            ]
        ) as? [URL] ?? []

        if !imageFileURLs.isEmpty {
            return imageFileURLs.compactMap(NSImage.init(contentsOf:))
        }

        let hasText = !(pasteboard.string(forType: .string)?.trim().isEmpty ?? true)
        guard !hasText, let image = NSImage(pasteboard: pasteboard) else {
            return []
        }
        return [image]
    }

    /// Shows an open panel for image files and returns the chosen images.
    @objc
    static func chooseImages(completion: @escaping ([NSImage]) -> ()) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "conversation.image.open_panel.message")

        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in
            guard response == .OK else {
                completion([])
                return
            }
            completion(panel.urls.compactMap(NSImage.init(contentsOf:)))
        }
    }
}
