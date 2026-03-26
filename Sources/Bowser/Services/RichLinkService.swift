// RichLinkService.swift - Rich Hyperlink Clipboard Utility
// Writes a URL + title as a multi-format rich hyperlink to NSPasteboard.
// Recipient apps pick the richest format they support:
//   Slack / Notion / web → HTML anchor tag
//   Mail / Pages / Notes → RTF with .link attribute
//   Terminal / plain text → raw URL string

import AppKit
import Foundation

extension NSPasteboard {

    /// Write a URL to the pasteboard as a rich hyperlink.
    ///
    /// Three representations are written simultaneously so every destination
    /// app gets the best format it understands:
    /// - `.string`  — raw URL (plain-text fallback)
    /// - `.html`    — `<a href="…">Title</a>` (Slack, Notion, Gmail web, etc.)
    /// - `.rtf`     — NSAttributedString with `.link` attribute (Mail, Pages, Notes, TextEdit)
    func setRichLink(title: String, url: URL) {
        let urlString = url.absoluteString
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = displayTitle.isEmpty ? urlString : displayTitle

        clearContents()

        // 1. Plain-text URL — universal fallback
        setString(urlString, forType: .string)

        // 2. HTML anchor — used by Slack, Notion, Gmail web, etc.
        let escapedLabel = label
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let html = "<a href=\"\(urlString)\">\(escapedLabel)</a>"
        setString(html, forType: .html)

        // 3. RTF with hyperlink attribute — used by Mail, Pages, Notes, TextEdit
        let attributed = NSMutableAttributedString(string: label)
        let range = NSRange(location: 0, length: attributed.length)
        attributed.addAttribute(.link, value: url, range: range)
        if let rtfData = try? attributed.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            setData(rtfData, forType: .rtf)
        }
    }
}
