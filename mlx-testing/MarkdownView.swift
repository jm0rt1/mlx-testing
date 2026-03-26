import SwiftUI

// MARK: - MarkdownView

/// A lightweight Markdown renderer that handles the most common block-level
/// elements produced by LLMs: paragraphs, fenced code blocks, headings,
/// unordered lists, ordered lists, and horizontal rules.
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    // MARK: - Block types

    private enum Block {
        case paragraph(String)
        case codeBlock(language: String?, code: String)
        case heading(level: Int, text: String)
        case unorderedList([String])
        case orderedList([(Int, String)])
        case horizontalRule
    }

    // MARK: - Parser

    private func parseBlocks() -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block: ```lang ... ```
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                let opener = line.trimmingCharacters(in: .whitespaces)
                let lang = String(opener.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let cl = lines[i]
                    if cl.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(cl)
                    i += 1
                }
                blocks.append(.codeBlock(
                    language: lang.isEmpty ? nil : lang,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Heading: # ... #### (up to 4 levels)
            if let match = line.range(of: #"^(#{1,4})\s+(.+)$"#, options: .regularExpression) {
                let full = String(line[match])
                let hashCount = full.prefix(while: { $0 == "#" }).count
                let headingText = String(full.drop(while: { $0 == "#" }).dropFirst()) // drop the space
                blocks.append(.heading(level: hashCount, text: headingText))
                i += 1
                continue
            }

            // Horizontal rule: ---, ***, ___
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count >= 3 && (
                trimmed.allSatisfy({ $0 == "-" }) ||
                trimmed.allSatisfy({ $0 == "*" }) ||
                trimmed.allSatisfy({ $0 == "_" })
            ) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Unordered list: lines starting with - or *
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let li = lines[i].trimmingCharacters(in: .whitespaces)
                    if li.hasPrefix("- ") {
                        items.append(String(li.dropFirst(2)))
                    } else if li.hasPrefix("* ") {
                        items.append(String(li.dropFirst(2)))
                    } else if li.isEmpty {
                        break
                    } else {
                        // Continuation of previous item
                        if !items.isEmpty {
                            items[items.count - 1] += " " + li
                        }
                    }
                    i += 1
                }
                if !items.isEmpty {
                    blocks.append(.unorderedList(items))
                }
                continue
            }

            // Ordered list: lines starting with 1. 2. etc
            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                var items: [(Int, String)] = []
                while i < lines.count {
                    let li = lines[i].trimmingCharacters(in: .whitespaces)
                    if let match = li.range(of: #"^(\d+)\.\s(.*)$"#, options: .regularExpression) {
                        let full = String(li[match])
                        let numEnd = full.firstIndex(of: ".")!
                        let num = Int(full[full.startIndex..<numEnd]) ?? items.count + 1
                        let content = String(full[full.index(numEnd, offsetBy: 2)...])
                        items.append((num, content))
                    } else if li.isEmpty {
                        break
                    } else if !items.isEmpty {
                        items[items.count - 1].1 += " " + li
                    }
                    i += 1
                }
                if !items.isEmpty {
                    blocks.append(.orderedList(items))
                }
                continue
            }

            // Empty line — skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Paragraph: accumulate consecutive non-empty lines
            var paraLines: [String] = []
            while i < lines.count {
                let pl = lines[i]
                let pt = pl.trimmingCharacters(in: .whitespaces)
                if pt.isEmpty || pt.hasPrefix("```") || pt.hasPrefix("#") ||
                   pt.hasPrefix("- ") || pt.hasPrefix("* ") ||
                   pt.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                    break
                }
                paraLines.append(pl)
                i += 1
            }
            if !paraLines.isEmpty {
                blocks.append(.paragraph(paraLines.joined(separator: "\n")))
            }
        }

        return blocks
    }

    // MARK: - Block renderers

    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .paragraph(let text):
            inlineMarkdown(text)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)

        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .unorderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                            .fontWeight(.bold)
                        inlineMarkdown(item)
                    }
                }
            }

        case .orderedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(item.0).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        inlineMarkdown(item.1)
                    }
                }
            }

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Code block

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language, !lang.isEmpty {
                HStack {
                    Text(lang)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .background(Color.black.opacity(0.3))
            }

            Text(code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.black.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    // MARK: - Heading

    @ViewBuilder
    private func headingView(level: Int, text: String) -> some View {
        switch level {
        case 1:
            inlineMarkdown(text).font(.title2).fontWeight(.bold)
        case 2:
            inlineMarkdown(text).font(.title3).fontWeight(.semibold)
        case 3:
            inlineMarkdown(text).font(.headline)
        default:
            inlineMarkdown(text).font(.subheadline).fontWeight(.semibold)
        }
    }

    // MARK: - Inline markdown (bold, italic, code, links)

    @ViewBuilder
    private func inlineMarkdown(_ string: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(string)
        }
    }
}
