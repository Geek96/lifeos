import Foundation

// 睡眠：`健康/睡眠/YYYY-MM.md`，一个月一个文件，表 `| 日期 | 入睡 | 起床 | 时长 |`，一晚一行。
// 日期是起床那天；agent 写、App 只读。

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
}

extension HealthFormat {
    /// 450 → “7 小时 30 分”
    public static func sleepText(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return total % 60 == 0 ? "\(total / 60) 小时" : "\(total / 60) 小时 \(total % 60) 分"
    }
}
