import Foundation

// 体重：`健康/体重.md`，一张表 `| 日期 | 体重（lb） | 备注 |`，一次一行（每周挑一天早上空腹称）。
// agent 和 App（营养页的“记体重”）都可以写。目标的增减速度写在 `健康/目标.md` 的
// `weight_gain_min` / `weight_gain_max`（每月多少 kg，减重写负数），从目标的 `since` 起算。

/// 一次称重
public struct WeightEntry: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var lb: Double
    public var note: String

    public var kg: Double { lb * WeightEntry.kgPerLb }
    public static let kgPerLb = 0.45359237
}

/// 体重目标：从 since 起每月变化 min…max kg
public struct WeightPlan: Equatable, Sendable {
    public var since: Date?
    public var minKgPerMonth: Double
    public var maxKgPerMonth: Double

    /// 从起点（某次称重）出发，到 date 时目标范围（lb）
    public func band(from base: WeightEntry, at date: Date) -> (low: Double, high: Double) {
        let months = max(date.timeIntervalSince(base.date), 0) / (30.44 * 86400)
        let a = base.lb + minKgPerMonth * months / WeightEntry.kgPerLb
        let b = base.lb + maxKgPerMonth * months / WeightEntry.kgPerLb
        return (min(a, b), max(a, b))
    }
}

extension HealthSnapshot {
    /// 体重目标的起点：目标生效那天（含）之前最近的一次称重；没有就用第一次
    public var weightBaseline: WeightEntry? {
        guard let since = weightPlan?.since else { return weights.first }
        return weights.last { $0.date <= since } ?? weights.first
    }

    /// 截至 date 最近一次称重，和 days 天前（含）最近一次比，变了多少 lb；不够两次就 nil
    public func weightChange(days: Int, until date: Date, calendar: Calendar) -> Double? {
        guard let latest = weights.last(where: { $0.date <= date }),
              let cutoff = calendar.date(byAdding: .day, value: -days, to: latest.date),
              let earlier = weights.last(where: { $0.date <= cutoff }) else { return nil }
        return latest.lb - earlier.lb
    }
}

extension HealthStore {
    public var weightURL: URL { root.appendingPathComponent("体重.md") }

    public func loadWeights(calendar: Calendar = .current) -> [WeightEntry] {
        guard let text = try? String(contentsOf: weightURL, encoding: .utf8) else { return [] }
        return Self.parseWeights(text, calendar: calendar)
    }

    /// 第一张表头含“体重”的表；列名写了 kg 就按 kg 换算成 lb。同一天两行取后一行
    static func parseWeights(_ text: String, calendar: Calendar) -> [WeightEntry] {
        let body = Frontmatter.parse(text).body
        guard let table = MarkdownTable.tables(in: body).first(where: { $0.header.contains { $0.contains("体重") } }) else { return [] }
        let h = table.header
        let di = h.firstIndex { $0.contains("日期") } ?? 0
        let wi = h.firstIndex { $0.contains("体重") } ?? 1
        let ni = h.firstIndex { $0.contains("备注") }
        let inKg = h[wi].lowercased().contains("kg")
        var byDay: [Date: WeightEntry] = [:]
        for cells in table.rows {
            func cell(_ j: Int?) -> String { j.map { $0 < cells.count ? cells[$0].trimmingCharacters(in: .whitespaces) : "" } ?? "" }
            guard let date = DateText.parse(cell(di), calendar: calendar) else { continue }
            let raw = cell(wi)
            guard let n = number(raw) else { continue }
            // 单元格自己写了单位就按单元格的（“144 lb（65.3 kg）”按 lb）
            let kg = unitIsKg(raw) ?? inKg
            let day = calendar.startOfDay(for: date)
            byDay[day] = WeightEntry(date: day, lb: kg ? n / WeightEntry.kgPerLb : n, note: cell(ni))
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// “145”“145 lb”“145磅” → 145；“65.8 kg”“65.8公斤” → 换成 lb；不是数字就 nil
    public static func parseWeightInput(_ s: String) -> Double? {
        guard let n = number(s), n > 0 else { return nil }
        return unitIsKg(s) == true ? n / WeightEntry.kgPerLb : n
    }

    /// 第一个数字后面紧跟的单位：kg / 公斤 / 千克 → true，lb / 磅 → false，没写 → nil
    static func unitIsKg(_ s: String) -> Bool? {
        let t = s.lowercased().replacingOccurrences(of: ",", with: "")
        guard let r = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        let rest = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        if ["kg", "公斤", "千克"].contains(where: rest.hasPrefix) { return true }
        if ["lb", "磅"].contains(where: rest.hasPrefix) { return false }
        return nil
    }

    public enum WeightEntryError: LocalizedError, Equatable {
        case badWeight(String)
        public var errorDescription: String? {
            switch self { case .badWeight(let s): "“\(s)”不是体重，写成 145 或 65.8 kg 这样" }
        }
    }

    static let weightHeader = "| 日期 | 体重（lb） | 备注 |\n|---|---|---|"

    /// 记一次体重（存成 lb，保留一位小数）；同一天再记就替换。返回改动前的内容（撤销用，新建时为 nil）
    @discardableResult
    public func recordWeight(day: Date, value: String, note: String = "", calendar: Calendar = .current) throws -> String? {
        guard let lb = Self.parseWeightInput(value) else { throw WeightEntryError.badWeight(value) }
        let dayText = DateText.format(day, withTime: false, calendar: calendar)
        let cleanNote = note.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
        let row = "| \(dayText) | \(String(format: "%.1f", lb)) | \(cleanNote) |"
        guard let before = try? String(contentsOf: weightURL, encoding: .utf8) else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let text = "---\ntype: health-weight\n---\n# 体重\n\n每周挑一天早上空腹称，一次一行。\n\n\(Self.weightHeader)\n\(row)\n"
            try text.write(to: weightURL, atomically: true, encoding: .utf8)
            return nil
        }
        try Self.upsertDatedRow(row, day: dayText, headerMarker: "体重", header: Self.weightHeader, into: before)
            .write(to: weightURL, atomically: true, encoding: .utf8)
        return before
    }

    /// `目标.md` 里的体重目标（没写 weight_gain_min / max 就没有）
    public func loadWeightPlan(calendar: Calendar = .current) -> WeightPlan? {
        guard let text = try? String(contentsOf: targetsURL, encoding: .utf8) else { return nil }
        return Self.parseWeightPlan(text, calendar: calendar)
    }

    static func parseWeightPlan(_ text: String, calendar: Calendar) -> WeightPlan? {
        let f = Frontmatter.parse(text).fields
        guard let lo = f["weight_gain_min"].flatMap(signedNumber), let hi = f["weight_gain_max"].flatMap(signedNumber) else { return nil }
        let since = f["since"].flatMap { DateText.parse($0, calendar: calendar) }.map { calendar.startOfDay(for: $0) }
        return WeightPlan(since: since, minKgPerMonth: lo, maxKgPerMonth: hi)
    }

    /// 带正负号的数字（“-0.5”“+1”）
    static func signedNumber(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let n = number(t) else { return nil }
        return t.hasPrefix("-") || t.hasPrefix("−") ? -abs(n) : n
    }
}
