// RichTextEditor.swift - NSTextView wrapper for rich text editing
// Supports bold, italic, headings, images, hyperlinks via RTFD

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Rich Text Editor (NSViewRepresentable)
// =============================================================================

/// Wraps NSTextView in an NSScrollView for full rich-text editing.
/// Content is round-tripped as RTFD Data which natively supports formatted
/// text, inline images, and clickable hyperlinks.
struct RichTextEditor: NSViewRepresentable {

    @Binding var rtfdData: Data
    var onTextChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.isAutomaticDataDetectionEnabled = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true

        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false

        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        loadContent(into: textView, coordinator: context.coordinator)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only reload when RTFD data changed externally (not from our own edits)
        if !context.coordinator.isUpdatingFromTextView {
            let currentData = textView.textStorage?.rtfd(
                from: NSRange(location: 0, length: textView.textStorage?.length ?? 0),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            if currentData != rtfdData {
                loadContent(into: textView, coordinator: context.coordinator)
            }
        }
    }

    private func loadContent(into textView: NSTextView, coordinator: Coordinator) {
        coordinator.isLoadingContent = true
        defer { coordinator.isLoadingContent = false }

        if rtfdData.isEmpty {
            textView.string = ""
            textView.font = .systemFont(ofSize: 14)
            textView.textColor = .textColor
            return
        }

        if let attrString = NSAttributedString(
            rtfd: rtfdData,
            documentAttributes: nil
        ) {
            textView.textStorage?.setAttributedString(attrString)
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?
        var isUpdatingFromTextView = false
        var isLoadingContent = false

        init(parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoadingContent else { return }
            guard let textView = notification.object as? NSTextView,
                  let storage = textView.textStorage
            else { return }

            isUpdatingFromTextView = true
            let range = NSRange(location: 0, length: storage.length)
            if let data = storage.rtfd(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            ) {
                parent.rtfdData = data
            }
            isUpdatingFromTextView = false
            parent.onTextChange?()
        }
    }
}

// =============================================================================
// MARK: - Formatting Commands
// =============================================================================

extension RichTextEditor.Coordinator {

    /// Toggle bold on the current selection
    func toggleBold() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            let manager = NSFontManager.shared
            let newFont: NSFont
            if manager.traits(of: font).contains(.boldFontMask) {
                newFont = manager.convert(font, toNotHaveTrait: .boldFontMask)
            } else {
                newFont = manager.convert(font, toHaveTrait: .boldFontMask)
            }
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
        notifyChange()
    }

    /// Toggle italic on the current selection
    func toggleItalic() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
            guard let font = value as? NSFont else { return }
            let manager = NSFontManager.shared
            let newFont: NSFont
            if manager.traits(of: font).contains(.italicFontMask) {
                newFont = manager.convert(font, toNotHaveTrait: .italicFontMask)
            } else {
                newFont = manager.convert(font, toHaveTrait: .italicFontMask)
            }
            storage.addAttribute(.font, value: newFont, range: subRange)
        }
        storage.endEditing()
        notifyChange()
    }

    /// Toggle underline on the current selection
    func toggleUnderline() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()
        storage.enumerateAttribute(.underlineStyle, in: range) { value, subRange, _ in
            let current = (value as? Int) ?? 0
            let newValue = current == 0 ? NSUnderlineStyle.single.rawValue : 0
            storage.addAttribute(.underlineStyle, value: newValue, range: subRange)
        }
        storage.endEditing()
        notifyChange()
    }

    /// Apply heading style (size 22 bold for H1, 18 bold for H2, 15 bold for H3)
    func applyHeading(_ level: Int) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        let sizes: [Int: CGFloat] = [1: 24, 2: 20, 3: 16]
        let fontSize = sizes[level] ?? 14

        storage.beginEditing()
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        storage.addAttribute(.font, value: font, range: range)
        storage.endEditing()
        notifyChange()
    }

    /// Toggle a bulleted list prefix on selected lines
    func toggleBulletList() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()

        let text = storage.string as NSString
        let lineRange = text.lineRange(for: range)
        let lineText = text.substring(with: lineRange)

        storage.beginEditing()
        if lineText.hasPrefix("• ") {
            let stripped = lineText.replacingOccurrences(of: "• ", with: "", options: [], range: lineText.startIndex..<lineText.index(lineText.startIndex, offsetBy: min(2, lineText.count)))
            storage.replaceCharacters(in: lineRange, with: stripped)
        } else {
            storage.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "• ")
        }
        storage.endEditing()
        notifyChange()
    }

    /// Insert a hyperlink on the current selection
    func insertLink(url: URL) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        storage.beginEditing()
        storage.addAttribute(.link, value: url, range: range)
        storage.addAttribute(.foregroundColor, value: NSColor.linkColor, range: range)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        storage.endEditing()
        notifyChange()
    }

    private func notifyChange() {
        guard let textView, let storage = textView.textStorage else { return }
        isUpdatingFromTextView = true
        let range = NSRange(location: 0, length: storage.length)
        if let data = storage.rtfd(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ) {
            parent.rtfdData = data
        }
        isUpdatingFromTextView = false
        parent.onTextChange?()
    }
}
