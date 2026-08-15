import AppKit
import SwiftUI

struct DeveloperResponseView: View {
    let text: String

    private var segments: [ResponseSegment] {
        MarkdownResponseParser.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                switch segment.content {
                case .prose(let value):
                    Text(verbatim: value)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let value):
                    MOPCodeBlock(language: language, code: value)
                }
            }
        }
    }
}

private struct ResponseSegment: Identifiable {
    enum Content {
        case prose(String)
        case code(language: String, String)
    }

    let id: Int
    let content: Content
}

private enum MarkdownResponseParser {
    static func parse(_ text: String) -> [ResponseSegment] {
        let lines = text.components(separatedBy: "\n")
        var rawSegments: [ResponseSegment.Content] = []
        var proseLines: [String] = []
        var codeLines: [String] = []
        var language = ""
        var insideCodeBlock = false

        for line in lines {
            if line.hasPrefix("```") {
                if insideCodeBlock {
                    rawSegments.append(.code(language: language, codeLines.joined(separator: "\n")))
                    codeLines.removeAll(keepingCapacity: true)
                    language = ""
                } else {
                    let prose = proseLines.joined(separator: "\n")
                    if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        rawSegments.append(.prose(prose))
                    }
                    proseLines.removeAll(keepingCapacity: true)
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                insideCodeBlock.toggle()
                continue
            }

            if insideCodeBlock {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }

        if insideCodeBlock {
            rawSegments.append(.code(language: language, codeLines.joined(separator: "\n")))
        } else {
            let prose = proseLines.joined(separator: "\n")
            if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rawSegments.append(.prose(prose))
            }
        }

        return rawSegments.enumerated().map { ResponseSegment(id: $0.offset, content: $0.element) }
    }
}

struct MOPCodeBlock: View {
    let language: String
    let code: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        didCopy = false
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, design: .monospaced))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(didCopy ? .green : .secondary)
                .accessibilityLabel(didCopy ? "Code copied" : "Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            SyntaxHighlightedCode(code: code)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }
}

private struct SyntaxHighlightedCode: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(code.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 24, alignment: .trailing)

                        highlightedLine(line)
                            .font(.system(size: 12, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .textSelection(.enabled)
    }

    private func highlightedLine(_ line: String) -> Text {
        SyntaxHighlighter.highlight(line)
    }
}

private enum SyntaxHighlighter {
    private static let keywordSet: Set<String> = [
        "actor", "async", "await", "break", "case", "catch", "class", "const", "continue", "def",
        "else", "enum", "extension", "for", "func", "guard", "if", "import", "in", "let", "match",
        "new", "nil", "private", "protocol", "public", "return", "self", "static", "struct", "switch",
        "throw", "throws", "try", "var", "where", "while", "async", "await", "function", "interface",
        "type", "from", "as", "is", "true", "false", "None", "True", "False"
    ]

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"//.*|#.*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b[A-Za-z_][A-Za-z0-9_]*\b|\b\d+(?:\.\d+)?\b"#
    )

    static func highlight(_ line: String) -> Text {
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = tokenRegex.matches(in: line, range: fullRange)
        var result = Text("")
        var cursor = line.startIndex

        for match in matches {
            guard let range = Range(match.range, in: line) else { continue }
            if cursor < range.lowerBound {
                result = result + Text(verbatim: String(line[cursor..<range.lowerBound])).foregroundStyle(.primary)
            }

            let token = String(line[range])
            result = result + Text(verbatim: token).foregroundStyle(color(for: token))
            cursor = range.upperBound
        }

        if cursor < line.endIndex {
            result = result + Text(verbatim: String(line[cursor...])).foregroundStyle(.primary)
        }

        return result
    }

    private static func color(for token: String) -> Color {
        if token.hasPrefix("//") || token.hasPrefix("#") { return .secondary }
        if token.hasPrefix("\"") || token.hasPrefix("'") { return .orange }
        if keywordSet.contains(token) { return .purple }
        if Double(token) != nil { return .cyan }
        return .primary
    }
}
