import Foundation

/// LifeOS vault 的读写。App 只写：事项文件的时间/状态字段、新建事项、收件箱追加/删除一行。
/// 正文（准备信息）由 agent 写，App 不改。
public struct VaultStore: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    public var itemsDir: URL { root.appendingPathComponent("事项") }
    public var notesDir: URL { root.appendingPathComponent("备忘") }
    public var inboxURL: URL { root.appendingPathComponent("收件箱.md") }
    public var journalURL: URL { root.appendingPathComponent(".lifeos/journal.md") }
    public var rulesURL: URL { root.appendingPathComponent(".lifeos/RULES.md") }

    /// 看起来像不像 LifeOS vault（有 事项/ 或 .lifeos/）
    public var looksValid: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: itemsDir.path) || fm.fileExists(atPath: root.appendingPathComponent(".lifeos").path)
    }

    // MARK: - 事项

    public func loadItems(calendar: Calendar = .current) -> [LifeItem] {
        markdownFiles(in: itemsDir).compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).flatMap { LifeItem.parse(text: $0, fileURL: url, calendar: calendar) }
        }
    }

    /// 新建事项文件，返回路径。重名时加序号，不覆盖已有文件。
    public func createItem(kind: LifeItem.Kind, title: String, start: Date, end: Date?, startHasTime: Bool,
                           location: String = "", repeatRule: RepeatRule? = nil, estimateHours: Double? = nil,
                           now: Date = Date(), calendar: Calendar = .current) throws -> URL {
        try FileManager.default.createDirectory(at: itemsDir, withIntermediateDirectories: true)
        let day = DateText.format(start, withTime: false, calendar: calendar)
        let safeTitle = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        var url = itemsDir.appendingPathComponent("\(day) \(safeTitle).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = itemsDir.appendingPathComponent("\(day) \(safeTitle) \(n).md")
            n += 1
        }
        var lines = ["---", "type: life-item", "kind: \(kind.rawValue)", "title: \(Frontmatter.quote(title))",
                     "start: \(DateText.format(start, withTime: startHasTime, calendar: calendar))"]
        if let end { lines.append("end: \(DateText.format(end, withTime: kind == .event && startHasTime, calendar: calendar))") }
        if kind == .event && !startHasTime { lines.append("all_day: true") }
        if !location.isEmpty { lines.append("location: \(Frontmatter.quote(location))") }
        if let repeatRule { lines.append("repeat: \(repeatRule.text)") }
        if let estimateHours { lines.append("estimate: \(Self.hoursText(estimateHours))") }
        lines += ["added_by: user", "created: \(DateText.format(now, withTime: false, calendar: calendar))", "---", ""]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 改写事项的若干字段（nil = 删除该字段），正文不动。
    public func updateItem(at url: URL, set changes: [(String, String?)]) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        try Frontmatter.update(text, set: changes).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 移到新时间：event 整体平移（保持时长），其他类型只改 start。
    public func move(_ item: LifeItem, to newStart: Date, calendar: Calendar = .current) throws {
        var changes: [(String, String?)] = [("start", DateText.format(newStart, withTime: item.startHasTime, calendar: calendar))]
        if let end = item.end {
            let newEnd = end.addingTimeInterval(newStart.timeIntervalSince(item.start))
            changes.append(("end", DateText.format(newEnd, withTime: item.kind == .event && item.startHasTime, calendar: calendar)))
        }
        try updateItem(at: item.fileURL, set: changes)
    }

    /// 只改重复事项里的某一次：写入（或替换）`exceptions` 里这一天的那条；传 nil 或空改动 = 删掉这条（恢复原样）。
    /// 重复规则和其他字段不动；同一天原有的多条一并换掉。
    public func setException(_ exception: RecurrenceException?, forSeriesDate date: Date, of item: LifeItem,
                             calendar: Calendar = .current) throws {
        let text = try String(contentsOf: item.fileURL, encoding: .utf8)
        let day = calendar.startOfDay(for: date)
        let withTime = item.startHasTime && item.kind != .window
        // 现有的条目按原样（字符串）保留，只换这一天的
        var raw = Frontmatter.list(text, key: "exceptions")
        raw.removeAll { $0["date"].flatMap { DateText.parse($0, calendar: calendar) }.map(calendar.startOfDay) == day }
        var items: [[(String, String)]] = raw.map { dict in
            let order = ["date", "skip", "start", "end", "title", "location", "note"]
            return order.compactMap { k in dict[k].map { (k, $0) } }
                + dict.keys.filter { !order.contains($0) }.sorted().map { ($0, dict[$0]!) }
        }
        if var e = exception, !e.isEmpty {
            e.date = day
            items.append(e.fields(withTime: withTime, calendar: calendar))
        }
        items.sort { ($0.first?.1 ?? "") < ($1.first?.1 ?? "") }
        try Frontmatter.setList(text, key: "exceptions", items: items).write(to: item.fileURL, atomically: true, encoding: .utf8)
    }

    static func hoursText(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)
    }

    // MARK: - 收件箱

    public func inboxLines() -> [String] {
        guard let text = try? String(contentsOf: inboxURL, encoding: .utf8) else { return [] }
        return Frontmatter.parse(text).body.components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { return nil }
            let v = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
    }

    public func appendInbox(_ line: String) throws {
        let clean = line.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        var text = (try? String(contentsOf: inboxURL, encoding: .utf8)) ?? "---\ntype: life-inbox\n---\n# 收件箱\n\n"
        if !text.hasSuffix("\n") { text += "\n" }
        text += "- \(clean)\n"
        try text.write(to: inboxURL, atomically: true, encoding: .utf8)
    }

    /// 删除收件箱里第一条内容相同的行
    public func removeInbox(_ line: String) throws {
        let text = try String(contentsOf: inboxURL, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") && t.dropFirst(2).trimmingCharacters(in: .whitespaces) == line
        }) {
            lines.remove(at: i)
            try lines.joined(separator: "\n").write(to: inboxURL, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - 备忘

    public struct Note: Identifiable, Hashable, Sendable {
        public var id: String { url.path }
        public var url: URL
        public var title: String
        public var modified: Date
        public var preview: String
    }

    public func notes() -> [Note] {
        markdownFiles(in: notesDir).map { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let body = Frontmatter.parse(text).body
            let preview = body.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }.prefix(3).joined(separator: " ")
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Note(url: url, title: url.deletingPathExtension().lastPathComponent, modified: modified,
                        preview: String(preview.prefix(160)))
        }.sorted { $0.modified > $1.modified }
    }

    // MARK: - 工作日志

    public struct JournalEntry: Hashable, Sendable {
        public var heading: String
        public var lines: [String]
    }

    /// 最近几段 agent 日志（新的在前）
    public func recentJournal(limit: Int = 5) -> [JournalEntry] {
        guard let text = try? String(contentsOf: journalURL, encoding: .utf8) else { return [] }
        var entries: [JournalEntry] = []
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                entries.append(JournalEntry(heading: String(line.dropFirst(3)), lines: []))
            } else if !entries.isEmpty, line.hasPrefix("- ") {
                entries[entries.count - 1].lines.append(String(line.dropFirst(2)))
            }
        }
        return Array(entries.suffix(limit).reversed())
    }

    private func markdownFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
    }
}
