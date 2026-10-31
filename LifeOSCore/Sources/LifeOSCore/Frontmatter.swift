import Foundation

/// 极简 frontmatter：顶层 `key: value` 单行字段，外加一种块状列表（`list(_:key:)`，事项的 `exceptions` 用）。
/// 改写时只动目标行，其他内容逐字节保留。
public enum Frontmatter {
    public struct Document: Sendable {
        public var fields: [String: String]
        public var body: String
    }

    public static func parse(_ text: String) -> Document {
        let lines = text.components(separatedBy: "\n")
        guard let range = blockRange(lines) else { return Document(fields: [:], body: text) }
        var fields: [String: String] = [:]
        for line in lines[(range.lowerBound + 1)..<range.upperBound] {
            guard let (k, v) = keyValue(line) else { continue }
            fields[k] = v
        }
        let body = lines[(range.upperBound + 1)...].joined(separator: "\n")
        return Document(fields: fields, body: body)
    }

    /// 改写/新增/删除若干字段（值为 nil = 删除该行）。没有 frontmatter 时在开头新建。
    public static func update(_ text: String, set changes: [(String, String?)]) -> String {
        var lines = text.components(separatedBy: "\n")
        if blockRange(lines) == nil {
            lines = ["---", "---"] + lines
        }
        for (key, value) in changes {
            guard let range = blockRange(lines) else { break }
            let inner = (range.lowerBound + 1)..<range.upperBound
            if let i = inner.first(where: { keyValue(lines[$0])?.0 == key }) {
                // 原来是块状值（下面跟着缩进行）时，连同缩进行一起换掉
                let n = continuationCount(lines, after: i, before: range.upperBound)
                lines.removeSubrange((i + 1)..<(i + 1 + n))
                if let value { lines[i] = "\(key): \(quote(value))" } else { lines.remove(at: i) }
            } else if let value {
                lines.insert("\(key): \(quote(value))", at: range.upperBound)
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 读块状列表：
    /// ```
    /// exceptions:
    ///   - date: 2026-11-03
    ///     skip: true
    /// ```
    /// 每个 `- ` 开始一项，项里是 `key: value`。没有这个字段 = 空数组。
    public static func list(_ text: String, key: String) -> [[String: String]] {
        let lines = text.components(separatedBy: "\n")
        guard let range = blockRange(lines) else { return [] }
        guard let i = ((range.lowerBound + 1)..<range.upperBound).first(where: { keyValue(lines[$0])?.0 == key })
        else { return [] }
        let n = continuationCount(lines, after: i, before: range.upperBound)
        var result: [[String: String]] = []
        for line in lines[(i + 1)..<(i + 1 + n)] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t == "-" {
                result.append([:])
                t = String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            }
            guard !result.isEmpty, !t.isEmpty, !t.hasPrefix("#"), let (k, v) = keyValue(t) else { continue }
            result[result.count - 1][k] = v
        }
        return result
    }

    /// 写块状列表（整段替换；空数组 = 删掉这个字段）。每项按给的顺序写 `key: value`。
    public static func setList(_ text: String, key: String, items: [[(String, String)]]) -> String {
        var lines = text.components(separatedBy: "\n")
        if blockRange(lines) == nil { lines = ["---", "---"] + lines }
        guard let range = blockRange(lines) else { return text }
        var block: [String] = []
        for item in items where !item.isEmpty {
            for (j, (k, v)) in item.enumerated() {
                block.append((j == 0 ? "  - " : "    ") + "\(k): \(quote(v))")
            }
        }
        if let i = ((range.lowerBound + 1)..<range.upperBound).first(where: { keyValue(lines[$0])?.0 == key }) {
            let n = continuationCount(lines, after: i, before: range.upperBound)
            if block.isEmpty {
                lines.removeSubrange(i..<(i + 1 + n))
            } else {
                lines.replaceSubrange(i..<(i + 1 + n), with: ["\(key):"] + block)
            }
        } else if !block.isEmpty {
            lines.insert(contentsOf: ["\(key):"] + block, at: range.upperBound)
        }
        return lines.joined(separator: "\n")
    }

    /// 第 i 行之后紧跟着的缩进行（块状值的内容）有几行
    private static func continuationCount(_ lines: [String], after i: Int, before end: Int) -> Int {
        var n = 0
        while i + 1 + n < end {
            let l = lines[i + 1 + n]
            guard l.hasPrefix(" ") || l.hasPrefix("\t") else { break }
            n += 1
        }
        return n
    }

    public static func bool(_ s: String?) -> Bool? {
        switch s?.lowercased() { case "true", "yes": return true; case "false", "no": return false; default: return nil }
    }

    /// 需要时加引号（含冒号+空格、# 开头等会让 YAML 误读的值）
    static func quote(_ v: String) -> String {
        let risky = v.contains(": ") || v.hasPrefix("#") || v.hasPrefix("[") || v.hasPrefix("{")
            || v.hasPrefix("\"") || v.hasPrefix("'") || v.hasPrefix("@") || v.hasPrefix("*")
        guard risky else { return v }
        return "\"" + v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// 第一行 --- 到下一个 --- 的行号区间
    private static func blockRange(_ lines: [String]) -> ClosedRange<Int>? {
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        guard let close = lines.indices.dropFirst().first(where: {
            lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else { return nil }
        return 0...close
    }

    private static func keyValue(_ line: String) -> (String, String)? {
        guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉行尾注释（引号外的 " #"）
        if !value.hasPrefix("\""), !value.hasPrefix("'"), let hash = value.range(of: " #") {
            value = value[..<hash.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        return (key, value)
    }
}
