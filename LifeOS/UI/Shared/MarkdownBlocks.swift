import SwiftUI
import LifeOSCore

/// 正文显示：普通行按行内 Markdown 渲染（标题加粗、列表加圆点），`| … |` 表格画成真正的表格。
struct MarkdownBlocks: View {
    let text: String

    enum Block {
        case text(String)
        case table(MarkdownTable.Table)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ForEach(Array(Self.split(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let s): Text(Self.inline(s)).textSelection(.enabled)
                case .table(let t): MarkdownTableView(table: t)
                }
            }
        }
    }

    /// 连续的 `|` 行是一张表（第二行得是分隔行），其余按段落归在一起
    static func split(_ text: String) -> [Block] {
        var out: [Block] = []
        var prose: [String] = []
        var rows: [String] = []
        func flushProse() {
            let s = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !s.trimmingCharacters(in: .whitespaces).isEmpty { out.append(.text(s)) }
            prose = []
        }
        func flushRows() {
            guard !rows.isEmpty else { return }
            if let t = MarkdownTable.tables(in: rows.joined(separator: "\n")).first {
                flushProse()
                out.append(.table(t))
            } else {
                prose += rows
            }
            rows = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                rows.append(line)
            } else {
                flushRows()
                prose.append(line)
            }
        }
        flushRows()
        flushProse()
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        let lines = s.components(separatedBy: "\n").map { line -> String in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { return "**" + t.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces) + "**" }
            if t.hasPrefix("- ") || t.hasPrefix("* ") { return "• " + t.dropFirst(2) }
            if t.hasPrefix("> ") { return "_" + t.dropFirst(2) + "_" }
            return line
        }
        let text = lines.joined(separator: "\n")
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

struct MarkdownTableView: View {
    let table: MarkdownTable.Table

    private var columns: Int { max(table.header.count, table.rows.map(\.count).max() ?? 0) }

    /// 补齐空格子，让每行列数一样
    private func cells(_ row: [String]) -> [String] { row + Array(repeating: "", count: max(0, columns - row.count)) }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(cells(table.header).enumerated()), id: \.offset) { _, h in
                    Text(MarkdownBlocks.inline(h)).fontWeight(.semibold).foregroundStyle(.secondary)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { i, row in
                GridRow {
                    ForEach(Array(cells(row).enumerated()), id: \.offset) { _, c in
                        Text(MarkdownBlocks.inline(c)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if i < table.rows.count - 1 {
                    Divider().opacity(0.5).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .textSelection(.enabled)
        .padding(Theme.Space.s)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}
