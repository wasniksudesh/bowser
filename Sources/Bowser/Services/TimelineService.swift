// TimelineService.swift - Per-folder timeline note management
// Handles auto-creation and appending entries (text + images) to the Timeline note

import AppKit
import Foundation

// =============================================================================
// MARK: - Timeline Service
// =============================================================================

/// Manages the special Timeline note that exists in every folder.
/// The Timeline is a changelog-style note that captures user-saved selections
/// and snapshots with timestamps and source URLs.
@MainActor
final class TimelineService {

    static let shared = TimelineService()

    private init() {}

    // MARK: - Public API

    /// Ensure the timeline note exists for a folder, creating it if absent.
    @discardableResult
    func ensureTimelineNote(forFolder folderId: UUID) -> Note {
        let timelineId = Note.timelineNoteId(forFolder: folderId)
        if let existing = NotePersistence.shared.loadNote(id: timelineId, forFolder: folderId) {
            return existing
        }
        let note = Note(
            id: timelineId,
            title: "Timeline",
            isTimeline: true
        )
        NotePersistence.shared.saveNote(note, forFolder: folderId)
        return note
    }

    /// Append a text selection entry to the timeline.
    func appendTextEntry(text: String, url: URL?, toFolder folderId: UUID) {
        var note = ensureTimelineNote(forFolder: folderId)

        let entry = buildTextEntry(text: text, url: url)
        note.contentRTFD = prependEntry(entry, to: note.contentRTFD)
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    /// Append a text selection entry to a specific note (in addition to the timeline).
    func appendTextEntry(text: String, url: URL?, toNote noteId: UUID, inFolder folderId: UUID) {
        guard var note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) else {
            return
        }
        let entry = buildTextEntry(text: text, url: url)
        note.contentRTFD = prependEntry(entry, to: note.contentRTFD)
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    /// Append a snapshot entry to the timeline.
    func appendSnapshotEntry(image: NSImage, url: URL?, toFolder folderId: UUID) {
        var note = ensureTimelineNote(forFolder: folderId)

        let entry = buildSnapshotEntry(image: image, url: url)
        note.contentRTFD = prependEntry(entry, to: note.contentRTFD)
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    /// Append a snapshot entry to a specific note (in addition to the timeline).
    func appendSnapshotEntry(image: NSImage, url: URL?, toNote noteId: UUID, inFolder folderId: UUID) {
        guard var note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) else {
            return
        }
        let entry = buildSnapshotEntry(image: image, url: url)
        note.contentRTFD = prependEntry(entry, to: note.contentRTFD)
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    // MARK: - Entry Builders

    private func buildTextEntry(text: String, url: URL?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let timestampStr = Self.timestampFormatter.string(from: Date())
        let timestampAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(string: timestampStr, attributes: timestampAttrs))

        if let url {
            result.append(NSAttributedString(string: "  "))
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: url
            ]
            let displayURL = url.host ?? url.absoluteString
            result.append(NSAttributedString(string: displayURL, attributes: linkAttrs))
        }

        result.append(NSAttributedString(string: "\n"))

        let quoteAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: Self.quoteParagraphStyle
        ]
        result.append(NSAttributedString(string: text, attributes: quoteAttrs))
        result.append(NSAttributedString(string: "\n"))

        let dividerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.separatorColor
        ]
        result.append(NSAttributedString(string: "───────────────────────────\n\n", attributes: dividerAttrs))

        return result
    }

    private func buildSnapshotEntry(image: NSImage, url: URL?) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let timestampStr = Self.timestampFormatter.string(from: Date())
        let timestampAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        result.append(NSAttributedString(string: timestampStr + "  📸 Snapshot", attributes: timestampAttrs))

        if let url {
            result.append(NSAttributedString(string: "  "))
            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: url
            ]
            let displayURL = url.host ?? url.absoluteString
            result.append(NSAttributedString(string: displayURL, attributes: linkAttrs))
        }

        result.append(NSAttributedString(string: "\n"))

        let maxWidth: CGFloat = 480
        let scaledImage: NSImage
        if image.size.width > maxWidth {
            let scale = maxWidth / image.size.width
            scaledImage = NSImage(size: NSSize(width: maxWidth, height: image.size.height * scale))
            scaledImage.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: scaledImage.size))
            scaledImage.unlockFocus()
        } else {
            scaledImage = image
        }

        let attachment = NSTextAttachment()
        attachment.image = scaledImage
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "\n"))

        let dividerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.separatorColor
        ]
        result.append(NSAttributedString(string: "───────────────────────────\n\n", attributes: dividerAttrs))

        return result
    }

    // MARK: - Helpers

    /// Prepend a new entry to existing RTFD content (newest first).
    private func prependEntry(_ entry: NSAttributedString, to existingRTFD: Data) -> Data {
        let combined = NSMutableAttributedString(attributedString: entry)

        if !existingRTFD.isEmpty,
           let existing = NSAttributedString(rtfd: existingRTFD, documentAttributes: nil) {
            combined.append(existing)
        }

        let range = NSRange(location: 0, length: combined.length)
        return combined.rtfd(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ) ?? Data()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let quoteParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.headIndent = 12
        style.firstLineHeadIndent = 12
        style.paragraphSpacingBefore = 4
        return style
    }()
}
