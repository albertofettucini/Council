import CouncilKit
import AppKit
import UniformTypeIdentifiers

/// Exports a council session. Markdown is the primary, GitHub-friendly format; copy and a
/// paginated PDF are also offered. No options panel — sensible defaults.
enum Exporter {
    /// Present a save/open panel attached to the frontmost window. `runModal()` from inside a
    /// SwiftUI sheet (Settings) opens the panel BEHIND the sheet — it looks like the button did
    /// nothing. Attaching as a window-sheet is the correct macOS presentation; app-modal is the
    /// fallback when no window exists.
    private static func present(_ panel: NSSavePanel, then completion: @escaping (URL?) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { resp in
                completion(resp == .OK ? panel.url : nil)
            }
        } else {
            completion(panel.runModal() == .OK ? panel.url : nil)
        }
    }

    static func copy(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    static func saveMarkdown(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        present(panel) { url in
            guard let url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func savePDF(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).pdf"
        panel.allowedContentTypes = [.pdf]
        present(panel) { url in
            guard let url, let data = pdfData(markdown) else { return }
            try? data.write(to: url)
        }
    }

    // MARK: - PDF

    /// The export as a printable, paginated PDF: Letter or A4 pages (by the user's measurement
    /// system), margins, and the markdown laid out as styled text that breaks between lines.
    /// `dataWithPDF(inside:)` (and `NSPrintOperation.pdfOperation`, which sizes its one page to the
    /// view) put the whole session on ONE page as tall as the text, and `.full` markdown parsing
    /// dropped every paragraph break and style. Pages are laid out here, in-process: one text
    /// container per page, each drawn onto its own page of a PDF context. No print system involved.
    static func pdfData(_ markdown: String) -> Data? {
        let paper = Locale.current.measurementSystem == .us
            ? CGSize(width: 612, height: 792)          // US Letter
            : CGSize(width: 595.28, height: 841.89)    // A4
        let margin: CGFloat = 54
        let textArea = CGSize(width: paper.width - margin * 2, height: paper.height - margin * 2)

        // The layout manager flows the text through the containers in order, moving a line that
        // doesn't fit to the next page instead of cutting it.
        let storage = NSTextStorage(attributedString: printable(markdown))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var pages: [NSTextContainer] = []
        repeat {
            let page = NSTextContainer(size: textArea)
            page.lineFragmentPadding = 0
            layout.addTextContainer(page)
            layout.ensureLayout(for: page)
            pages.append(page)
            // A container that takes nothing (a line taller than a page) would loop forever.
            if pages.count > 1, layout.glyphRange(for: page).length == 0 { break }
        } while NSMaxRange(layout.glyphRange(for: pages[pages.count - 1])) < layout.numberOfGlyphs

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paper)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        let previous = NSGraphicsContext.current
        for page in pages {
            let glyphs = layout.glyphRange(for: page)
            if glyphs.length == 0, pages.count > 1 { continue }
            pdf.beginPDFPage(nil)
            pdf.saveGState()
            // AppKit text draws top-down: flip the page so y runs down from the top edge.
            pdf.translateBy(x: 0, y: paper.height)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            layout.drawBackground(forGlyphRange: glyphs, at: CGPoint(x: margin, y: margin))
            layout.drawGlyphs(forGlyphRange: glyphs, at: CGPoint(x: margin, y: margin))
            pdf.restoreGState()
            pdf.endPDFPage()
        }
        NSGraphicsContext.current = previous
        pdf.closePDF()
        return data.length > 0 ? data as Data : nil
    }

    /// Markdown → print-styled text, through the same block parser the app renders with.
    private static func printable(_ markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let body: CGFloat = 11
        let ink = NSColor.black
        let secondary = NSColor(white: 0.36, alpha: 1)
        func add(_ text: NSAttributedString, _ style: NSParagraphStyle) {
            let line = NSMutableAttributedString(attributedString: text)
            line.append(NSAttributedString(string: "\n"))
            line.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: line.length))
            out.append(line)
        }
        for block in MDBlock.parse(markdown) {
            switch block {
            case .heading(let level, let s):
                // # 18.5 · ## 16 · ### 13.5 · #### and below 11, all bold.
                let size = body + CGFloat(max(0, 4 - level)) * 2.5
                add(inline(s, size: size, bold: true, color: ink),
                    paragraphStyle(before: level <= 2 ? 16 : 10, after: 5))
            case .paragraph(let s):
                if s.count >= 3, s.allSatisfy({ "-*_ ".contains($0) }) {   // a horizontal rule
                    add(NSAttributedString(string: ""), paragraphStyle(after: 4))
                } else {
                    add(inline(s, size: body, color: ink), paragraphStyle(after: 7))
                }
            case .bullet(let s):
                let line = NSMutableAttributedString(string: "•\t", attributes: [.font: font(body), .foregroundColor: secondary])
                line.append(inline(s, size: body, color: ink))
                add(line, paragraphStyle(after: 4, indent: 4, hanging: 14))
            case .numbered(let n, let s):
                let line = NSMutableAttributedString(string: "\(n).\t", attributes: [.font: font(body, bold: true), .foregroundColor: secondary])
                line.append(inline(s, size: body, color: ink))
                add(line, paragraphStyle(after: 4, indent: 4, hanging: 18))
            case .quote(let s):
                add(inline(s, size: body, italic: true, color: secondary), paragraphStyle(after: 7, indent: 14))
            case .code(let code):
                add(NSAttributedString(string: code, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: body - 1.5, weight: .regular), .foregroundColor: ink]),
                    paragraphStyle(before: 2, after: 8, indent: 10))
            case .think(let reasoning):
                add(inline(reasoning.trimmingCharacters(in: .whitespacesAndNewlines), size: body - 1.5, italic: true, color: secondary),
                    paragraphStyle(after: 7, indent: 10))
            }
        }
        return out
    }

    /// One block's inline markdown (bold, italic, code, links) as fonts on a single paragraph.
    private static func inline(_ s: String, size: CGFloat, bold: Bool = false, italic: Bool = false,
                               color: NSColor) -> NSAttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: s, options: opts) else {
            return NSAttributedString(string: s, attributes: [.font: font(size, bold: bold, italic: italic), .foregroundColor: color])
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let f = intent.contains(.code)
                ? NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular)
                : font(size, bold: bold || intent.contains(.stronglyEmphasized),
                       italic: italic || intent.contains(.emphasized))
            var attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            if intent.contains(.strikethrough) { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attrs[.link] = link }
            out.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attrs))
        }
        return out
    }

    private static func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let f = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        guard italic else { return f }
        return NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.italic), size: size) ?? f
    }

    private static func paragraphStyle(before: CGFloat = 0, after: CGFloat, indent: CGFloat = 0,
                                       hanging: CGFloat = 0) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineSpacing = 1.5
        p.firstLineHeadIndent = indent
        p.headIndent = indent + hanging
        if hanging > 0 { p.tabStops = [NSTextTab(textAlignment: .left, location: indent + hanging)] }
        return p
    }

    // MARK: - Shareable council config (.council.json)

    /// Save a council config to a `.json` file the user can share / commit to GitHub.
    static func saveCouncil(_ config: CouncilConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        let panel = NSSavePanel()
        let safeName = config.name.replacingOccurrences(of: " ", with: "-").lowercased()
        panel.nameFieldStringValue = "\(safeName.isEmpty ? "council" : safeName).council.json"
        panel.allowedContentTypes = [.json]
        present(panel) { url in
            guard let url else { return }
            try? data.write(to: url)
        }
    }

    /// Open a `.json` council file the user picks; hands back nil if cancelled or invalid.
    static func openCouncil(_ completion: @escaping (CouncilConfig?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        present(panel) { url in
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(CouncilConfig.self, from: data),
                  !config.seats.isEmpty else { return completion(nil) }
            completion(config)
        }
    }
}
