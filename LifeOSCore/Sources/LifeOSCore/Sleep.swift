import Foundation

// 睡眠：`健康/睡眠/YYYY-MM.md`，一个月一个文件，表 `| 日期 | 入睡 | 起床 | 时长 |`，一晚一行。
// 日期是起床那天；agent 和 App（睡眠页的“记一晚”）都可以写。

/// 一晚的睡眠
public struct SleepNight: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    /// 起床那天（当天 0 点）
    public var date: Date
    /// 入睡时间，“HH:MM”；没说 = nil
    public var bedtime: String?
    /// 起床时间，“HH:MM”；没说 = nil
    public var wake: String?
    /// 睡了多少分钟：表里写了时长就用它，否则按入睡、起床算（跨午夜照算）
    public var minutes: Double?
}

extension HealthSnapshot {
    /// 某天早上那一次（起床在这天）
    public func sleep(on date: Date, calendar: Calendar) -> SleepNight? {
        sleep.last { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// 截至某天（含）最近 n 天里有时长的那几晚的平均分钟数
    public func averageSleep(days n: Int, until date: Date, calendar: Calendar) -> Double? {
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -(n - 1), to: end) else { return nil }
        let mins = sleep.filter { $0.date >= start && $0.date <= end }.compactMap(\.minutes)
        return mins.isEmpty ? nil : mins.reduce(0, +) / Double(mins.count)
    }
}

extension HealthStore {
    public var sleepDir: URL { root.appendingPathComponent("睡眠") }

    /// 所有月份文件里的每一晚，旧的在前；同一天写了两行取后一行
    public func loadSleep(calendar: Calendar = .current) -> [SleepNight] {
        var byDay: [Date: SleepNight] = [:]
        for url in Self.markdownFiles(in: sleepDir) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for night in Self.parseSleep(text, calendar: calendar) { byDay[night.date] = night }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 解析正文里第一张表头含“入睡”的表
    static func parseSleep(_ text: String, calendar: Calendar) -> [SleepNight] {
        let body = Frontmatter.parse(text).body
        guard let table = MarkdownTable.tables(in: body).first(where: { $0.header.contains { $0.contains("入睡") } }) else { return [] }
        let h = table.header
        func col(_ name: String) -> Int? { h.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(name) } }
        let di = col("日期") ?? 0, bi = col("入睡") ?? 1, wi = col("起床") ?? 2, li = col("时长")
        return table.rows.compactMap { cells in
            func cell(_ j: Int?) -> String? {
                guard let j, j < cells.count else { return nil }
                let t = cells[j].trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
            guard let dayText = cell(di), let date = DateText.parse(dayText, calendar: calendar) else { return nil }
            let bed = cell(bi).flatMap(clockMinutes) != nil ? cell(bi) : nil
            let wake = cell(wi).flatMap(clockMinutes) != nil ? cell(wi) : nil
            let mins = cell(li).flatMap(durationMinutes) ?? span(from: bed, to: wake)
            return SleepNight(date: calendar.startOfDay(for: date), bedtime: bed, wake: wake, minutes: mins)
        }
    }

    /// “23:40” → 1420；不是 HH:MM 就 nil
    static func clockMinutes(_ s: String) -> Double? {
        let p = s.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, let h = p[0], let m = p[1], (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return Double(h * 60 + m)
    }

    /// 时长：“7:30”（时:分）、“7.5h”、“7 小时”、“450 min”
    static func durationMinutes(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let p = t.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        if p.count == 2, let h = p[0], let m = p[1] { return h * 60 + m }
        guard let n = number(t) else { return nil }
        return t.lowercased().contains("min") || t.contains("分钟") ? n : n * 60
    }

    /// 入睡到起床的分钟数，起床早于入睡就当跨了午夜
    static func span(from bed: String?, to wake: String?) -> Double? {
        guard let b = bed.flatMap(clockMinutes), let w = wake.flatMap(clockMinutes) else { return nil }
        return w > b ? w - b : w + 1440 - b
    }

    // MARK: - 写入

    public enum SleepEntryError: LocalizedError, Equatable {
        case empty
        case badTime(String)

        public var errorDescription: String? {
            switch self {
            case .empty: "入睡、起床至少填一个"
            case .badTime(let s): "“\(s)”不是时间，写成 23:40 这样"
            }
        }
    }

    /// “7:5”“0710”“23：40” → “07:05”“07:10”“23:40”；不是时间就 nil
    public static func normalizedClock(_ s: String) -> String? {
        var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "：", with: ":")
        if !t.contains(":"), t.count == 4, Int(t) != nil { t.insert(":", at: t.index(t.startIndex, offsetBy: 2)) }
        guard let m = clockMinutes(t) else { return nil }
        let total = Int(m) % 1440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 起床那天所在月份的睡眠文件
    public func sleepURL(_ wakeDay: Date, calendar: Calendar = .current) -> URL {
        let month = DateText.format(wakeDay, withTime: false, calendar: calendar).prefix(7)
        return sleepDir.appendingPathComponent("\(month).md")
    }

    /// 记一晚：写进起床那天所在月份的文件。同一天已有一行就替换，没有就按日期插到对的位置；文件不存在就新建。
    /// 入睡、起床可以只给一个，另一个空着、时长也空着（不猜）。返回改动前的内容（撤销用，新建时为 nil）。
    @discardableResult
    public func recordSleep(wakeDay: Date, bedtime: String?, wake: String?, calendar: Calendar = .current) throws -> String? {
        func clean(_ s: String?) throws -> String? {
            guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            guard let n = Self.normalizedClock(s) else { throw SleepEntryError.badTime(s) }
            return n
        }
        let bed = try clean(bedtime), up = try clean(wake)
        guard bed != nil || up != nil else { throw SleepEntryError.empty }
        let day = DateText.format(wakeDay, withTime: false, calendar: calendar)
        let length = Self.span(from: bed, to: up).map { m in
            let total = Int(m.rounded())
            return "\(total / 60):" + String(format: "%02d", total % 60)
        }
        let row = "| \(day) | \(bed ?? "") | \(up ?? "") | \(length ?? "") |"
        let url = sleepURL(wakeDay, calendar: calendar)
        guard let before = try? String(contentsOf: url, encoding: .utf8) else {
            try FileManager.default.createDirectory(at: sleepDir, withIntermediateDirectories: true)
            let month = day.prefix(7)
            let text = "---\ntype: health-sleep\nmonth: \(month)\n---\n# \(month) 睡眠\n\n\(Self.sleepHeader)\n\(row)\n"
            try text.write(to: url, atomically: true, encoding: .utf8)
            return nil
        }
        try Self.upsertSleepRow(row, day: day, into: before).write(to: url, atomically: true, encoding: .utf8)
        return before
    }

    static let sleepHeader = "| 日期 | 入睡 | 起床 | 时长 |\n|---|---|---|---|"

    static func upsertSleepRow(_ row: String, day: String, into text: String) -> String {
        upsertDatedRow(row, day: day, headerMarker: "入睡", header: sleepHeader, into: text)
    }

    /// 按日期（`yyyy-MM-dd` 文本可以直接比大小）替换或插入一行：表头含 `headerMarker` 的那张表，
    /// 第一列是日期；找不到表就在末尾按 `header` 新建一张。睡眠、体重共用
    static func upsertDatedRow(_ row: String, day: String, headerMarker: String, header newHeader: String, into text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard let header = lines.firstIndex(where: { $0.hasPrefix("|") && $0.contains(headerMarker) }) else {
            var out = text
            if !out.hasSuffix("\n") { out += "\n" }
            return out + "\n\(newHeader)\n\(row)\n"
        }
        var i = header + 1
        if i < lines.count, lines[i].contains("---") { i += 1 }
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
            let first = lines[i].split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            if first == day { lines[i] = row; return lines.joined(separator: "\n") }
            if first > day { break }
            i += 1
        }
        lines.insert(row, at: i)
        return lines.joined(separator: "\n")
    }
}

extension HealthFormat {
    /// 450 → “7 小时 30 分”
    public static func sleepText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total % 60 == 0 ? "\(total / 60) 小时" : "\(total / 60) 小时 \(total % 60) 分"
    }
}
