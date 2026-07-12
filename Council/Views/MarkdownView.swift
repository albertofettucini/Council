import SwiftUI
import AppKit

/// A calm, lightweight markdown renderer: headings, lists, quotes, bold/italic/inline-code,
/// fenced code blocks (copy on hover), and collapsible <think> reasoning. Typography-first,
/// no heavy chrome — in keeping with the minimal-UI directive.
struct MarkdownView: View, Equatable {
    let text: String
    var baseSize: CGFloat = 14

    /// Parsing + AttributedString building is the most expensive body in the app. With this,
    /// `.equatable()` at the call sites lets SwiftUI SKIP re-parsing every finished card/panel
    /// whenever some OTHER view streams — only the view whose text actually changed re-runs.
    static func == (a: MarkdownView, b: MarkdownView) -> Bool {
        a.text == b.text && a.baseSize == b.baseSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MDBlock.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let s):
            inlineText(s)
                .font(.system(size: baseSize + CGFloat(max(0, 5 - level)) * 2.2, weight: .bold))
                .foregroundStyle(Blue.ink)
                .padding(.top, 2)
        case .paragraph(let s):
            inlineText(s).font(Blue.body(baseSize)).foregroundStyle(Blue.ink)
        case .bullet(let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(Blue.body(baseSize)).foregroundStyle(Blue.sub)
                inlineText(s).font(Blue.body(baseSize)).foregroundStyle(Blue.ink)
            }
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).").font(Blue.mono(baseSize - 1, .bold)).foregroundStyle(Blue.sub)
                inlineText(s).font(Blue.body(baseSize)).foregroundStyle(Blue.ink)
            }
        case .quote(let s):
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Blue.dim).frame(width: 2)
                inlineText(s).font(Blue.body(baseSize)).italic().foregroundStyle(Blue.sub)
            }
        case .code(let code):
            CodeBlockView(code: code)
        case .think(let reasoning):
            ThinkBlockView(reasoning: reasoning)
        }
    }

    private func inlineText(_ s: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: s, options: opts) {
            return Text(attr)
        }
        return Text(s)
    }
}

// MARK: - Code block (copy on hover)

private struct CodeBlockView: View {
    let code: String
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(Blue.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Blue.ink.opacity(0.05))
        .overlay(Rectangle().stroke(Blue.ink.opacity(0.5), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                } label: {
                    Text(copied ? "COPIED" : "COPY")
                        .font(Blue.mono(8, .bold)).tracking(1)
                        .foregroundStyle(Blue.paper)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Blue.ink)
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .onHover { hovering = $0; if !$0 { copied = false } }
    }
}

// MARK: - Collapsible reasoning (<think>…</think>)

private struct ThinkBlockView: View {
    let reasoning: String
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(Motion.view) { open.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text("REASONING").font(Blue.mono(9, .bold)).tracking(1.5)
                }
                .foregroundStyle(Blue.sub)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Text(reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(Blue.body(13)).foregroundStyle(Blue.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
        }
    }
}

// MARK: - Block model + parser

enum MDBlock {
    case heading(Int, String)
    case paragraph(String)
    case bullet(String)
    case numbered(String, String)
    case quote(String)
    case code(String)
    case think(String)

    /// Parse markdown text into blocks. Handles ``` fences and <think> blocks first,
    /// then headings / lists / quotes / paragraphs line-by-line.
    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !joined.isEmpty { blocks.append(.paragraph(joined)) }
                paragraph.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block
            if trimmed.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            // <think> reasoning block
            if trimmed.lowercased().hasPrefix("<think>") {
                flushParagraph()
                var body = [String(trimmed.dropFirst("<think>".count))]
                if trimmed.lowercased().contains("</think>") {
                    let inner = trimmed
                        .replacingOccurrences(of: "<think>", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive)
                    blocks.append(.think(inner)); i += 1; continue
                }
                i += 1
                while i < lines.count, !lines[i].lowercased().contains("</think>") {
                    body.append(lines[i]); i += 1
                }
                if i < lines.count {
                    body.append(lines[i].replacingOccurrences(of: "</think>", with: "", options: .caseInsensitive))
                    i += 1
                }
                blocks.append(.think(body.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty { flushParagraph(); i += 1; continue }

            // Heading
            if let h = headingLevel(trimmed) {
                flushParagraph()
                let content = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(h, content)); i += 1; continue
            }

            // Bullet
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2)))); i += 1; continue
            }

            // Numbered
            if let (num, rest) = numbered(trimmed) {
                flushParagraph()
                blocks.append(.numbered(num, rest)); i += 1; continue
            }

            // Quote
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                blocks.append(.quote(String(trimmed.dropFirst(2)))); i += 1; continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func headingLevel(_ s: String) -> Int? {
        var n = 0
        for c in s { if c == "#" { n += 1 } else { break } }
        if n >= 1, n <= 6, s.count > n, s[s.index(s.startIndex, offsetBy: n)] == " " { return n }
        return nil
    }

    private static func numbered(_ s: String) -> (String, String)? {
        guard let dot = s.firstIndex(of: ".") else { return nil }
        let numPart = s[s.startIndex..<dot]
        guard !numPart.isEmpty, numPart.allSatisfy(\.isNumber) else { return nil }
        let after = s.index(after: dot)
        guard after < s.endIndex, s[after] == " " else { return nil }
        return (String(numPart), String(s[s.index(after: after)...]))
    }
}
