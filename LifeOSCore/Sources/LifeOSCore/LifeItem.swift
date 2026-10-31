import Foundation

/// 一件生活事项（`事项/*.md` 的一份文件）。格式见 vault 的 `.lifeos/RULES.md`。
public struct LifeItem: Identifiable, Hashable, Sendable {
    /// 三种事项：约定（有起止时间）、期限（过了会出事）、时间窗（这段时间内找空办掉即可）。
    public enum Kind: String, CaseIterable, Sendable, Codable {
        case event, deadline, window

        public var label: String {
            switch self { case .event: return "约定"; case .deadline: return "期限"; case .window: return "时间窗" }
        }

        public var systemImage: String {
            switch self { case .event: return "calendar"; case .deadline: return "flag"; case .window: return "arrow.left.and.right" }
        }
    }

    /// 文件路径就是身份
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var kind: Kind
    public var title: String
    public var start: Date
    /// event 的结束；window 的结束日（含当天）；deadline 不用
    public var end: Date?
    /// start 只写了日期、没写时间
    public var startHasTime: Bool
    public var allDay: Bool
    public var location: String
    public var repeatRule: RepeatRule?
    public var repeatUntil: Date?
    public var remindDays: Int
    public var estimateHours: Double?
    public var done: Bool
    public var addedBy: String
    /// 正文（准备信息）
    public var body: String
    /// 属于哪个插件（如 `health`）；空 = 普通事项
    public var plugin: String
    /// 重复事项里单独某一次的改动（frontmatter 的 `exceptions`）；不重复的事项忽略
    public var exceptions: [RecurrenceException]

    public init(fileURL: URL, kind: Kind, title: String, start: Date, end: Date? = nil, startHasTime: Bool = true,
                allDay: Bool = false, location: String = "", repeatRule: RepeatRule? = nil, repeatUntil: Date? = nil,
                remindDays: Int = 3, estimateHours: Double? = nil, done: Bool = false, addedBy: String = "user",
                body: String = "", plugin: String = "", exceptions: [RecurrenceException] = []) {
        self.fileURL = fileURL
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.startHasTime = startHasTime
        self.allDay = allDay
        self.location = location
        self.repeatRule = repeatRule
        self.repeatUntil = repeatUntil
        self.remindDays = remindDays
        self.estimateHours = estimateHours
        self.done = done
        self.addedBy = addedBy
        self.body = body
        self.plugin = plugin
        self.exceptions = exceptions
    }

    /// event 的时长（秒）；没写结束时默认 1 小时
    public var duration: TimeInterval {
        guard let end, end > start else { return 3600 }
        return end.timeIntervalSince(start)
    }

    /// 按“事项文件”解析；不是 life-item 或缺必填字段时返回 nil。
    public static func parse(text: String, fileURL: URL, calendar: Calendar = .current) -> LifeItem? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        if let type = f["type"], !type.isEmpty, type != "life-item" { return nil }
        let title = f["title"].flatMap { $0.isEmpty ? nil : $0 }
            ?? fileURL.deletingPathExtension().lastPathComponent
        guard let startText = f["start"], let start = DateText.parse(startText, calendar: calendar) else { return nil }
        let kind = Kind(rawValue: f["kind"]?.lowercased() ?? "") ?? .event
        var end = f["end"].flatMap { DateText.parse($0, calendar: calendar) }
        // window 的结束日按“当天结束”算
        if kind == .window, let e = end, let text = f["end"], !DateText.hasTime(text) {
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: e))?.addingTimeInterval(-1)
        }
        return LifeItem(
            fileURL: fileURL,
            kind: kind,
            title: title,
            start: start,
            end: end,
            startHasTime: DateText.hasTime(startText),
            allDay: Frontmatter.bool(f["all_day"]) ?? !DateText.hasTime(startText),
            location: f["location"] ?? "",
            repeatRule: f["repeat"].flatMap(RepeatRule.parse),
            repeatUntil: f["repeat_until"].flatMap { DateText.parse($0, calendar: calendar) },
            remindDays: f["remind_days"].flatMap { Int($0) } ?? 3,
            estimateHours: f["estimate"].flatMap(Hours.parse),
            done: Frontmatter.bool(f["done"]) ?? false,
            addedBy: f["added_by"] ?? "user",
            body: doc.body.trimmingCharacters(in: .whitespacesAndNewlines),
            plugin: f["plugin"]?.lowercased() ?? "",
            exceptions: Frontmatter.list(text, key: "exceptions").compactMap {
                RecurrenceException.parse($0, seriesStart: start, seriesHasTime: DateText.hasTime(startText), calendar: calendar)
            }
        )
    }
}

/// 重复事项里单独一次的改动。`date` 是原本那一次的日期（0 点），用来对上是哪一次。
/// - `skip: true`：这一次取消，不显示。
/// - `start` / `end`：这一次挪到别的时间（可以挪到另一天）；只写 `start` 时按原时长平移。
/// - `title` / `location` / `note`：只改这一次的标题、地点、备注。
public struct RecurrenceException: Hashable, Sendable {
    public var date: Date
    public var skip: Bool
    public var start: Date?
    public var end: Date?
    public var title: String?
    public var location: String?
    public var note: String?

    public init(date: Date, skip: Bool = false, start: Date? = nil, end: Date? = nil,
                title: String? = nil, location: String? = nil, note: String? = nil) {
        self.date = date
        self.skip = skip
        self.start = start
        self.end = end
        self.title = title
        self.location = location
        self.note = note
    }

    /// 除了 date 什么都没写 = 不算改动
    public var isEmpty: Bool {
        !skip && start == nil && end == nil && title == nil && location == nil && note == nil
    }

    /// 从列表里的一项解析。没有能读懂的 `date` 时返回 nil。
    /// `start` 只写了日期而系列本身带时刻时，沿用系列的时刻（“挪到周四，时间不变”）；
    /// 这种情况下只写日期的 `end` 不用，结束按原时长算。
    static func parse(_ f: [String: String], seriesStart: Date, seriesHasTime: Bool, calendar: Calendar) -> RecurrenceException? {
        guard let dateText = f["date"], let date = DateText.parse(dateText, calendar: calendar) else { return nil }
        func when(_ key: String) -> Date? {
            guard let t = f[key], let d = DateText.parse(t, calendar: calendar) else { return nil }
            guard !DateText.hasTime(t), seriesHasTime else { return d }
            if key == "end" { return nil }
            let hm = calendar.dateComponents([.hour, .minute], from: seriesStart)
            return calendar.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: d)
        }
        func text(_ key: String) -> String? { f[key].flatMap { $0.isEmpty ? nil : $0 } }
        return RecurrenceException(date: calendar.startOfDay(for: date), skip: Frontmatter.bool(f["skip"]) ?? false,
                                   start: when("start"), end: when("end"),
                                   title: text("title"), location: text("location"), note: text("note"))
    }

    /// 写回 frontmatter 的字段（按固定顺序）
    public func fields(withTime: Bool, calendar: Calendar = .current) -> [(String, String)] {
        var r: [(String, String)] = [("date", DateText.format(date, withTime: false, calendar: calendar))]
        if skip { r.append(("skip", "true")) }
        if let start { r.append(("start", DateText.format(start, withTime: withTime, calendar: calendar))) }
        if let end { r.append(("end", DateText.format(end, withTime: withTime, calendar: calendar))) }
        if let title { r.append(("title", title)) }
        if let location { r.append(("location", location)) }
        if let note { r.append(("note", note)) }
        return r
    }
}

/// 重复规则：daily | weekly:mon,wed | monthly:15 | yearly
public enum RepeatRule: Hashable, Sendable {
    case daily
    /// 1 = 周日 … 7 = 周六（Calendar.weekday）
    case weekly(Set<Int>)
    case monthly(Int)
    case yearly

    static let weekdayNames = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]

    public static func parse(_ text: String) -> RepeatRule? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "daily" { return .daily }
        if t == "yearly" { return .yearly }
        if t == "weekly" { return .weekly([]) }
        if t.hasPrefix("weekly:") {
            let days = t.dropFirst(7).split(separator: ",").compactMap {
                weekdayNames[String($0.trimmingCharacters(in: .whitespaces).prefix(3))]
            }
            return .weekly(Set(days))
        }
        if t.hasPrefix("monthly") {
            let n = t.split(separator: ":").dropFirst().first.flatMap { Int($0) }
            return .monthly(n ?? 0)
        }
        return nil
    }

    public var text: String {
        switch self {
        case .daily: return "daily"
        case .yearly: return "yearly"
        case .monthly(let d): return d > 0 ? "monthly:\(d)" : "monthly"
        case .weekly(let days):
            let names = Self.weekdayNames.sorted { $0.value < $1.value }.filter { days.contains($0.value) }.map(\.key)
            return names.isEmpty ? "weekly" : "weekly:" + names.joined(separator: ",")
        }
    }

    public var label: String {
        switch self {
        case .daily: return "每天"
        case .yearly: return "每年"
        case .monthly(let d): return d > 0 ? "每月 \(d) 日" : "每月"
        case .weekly(let days):
            let names = ["", "日", "一", "二", "三", "四", "五", "六"]
            let order = [2, 3, 4, 5, 6, 7, 1].filter { days.contains($0) }
            return order.isEmpty ? "每周" : "每周" + order.map { names[$0] }.joined(separator: "、")
        }
    }
}

/// "2026-10-20 14:00" / "2026-10-20" / "2026-10-20T14:00"
public enum DateText {
    public static func parse(_ s: String, calendar: Calendar = .current) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "T", with: " ")
        for f in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            let df = DateFormatter()
            df.dateFormat = f
            df.timeZone = calendar.timeZone
            df.locale = Locale(identifier: "en_US_POSIX")
            if let d = df.date(from: t) { return d }
        }
        return nil
    }

    public static func hasTime(_ s: String) -> Bool { s.contains(":") }

    public static func format(_ d: Date, withTime: Bool, calendar: Calendar = .current) -> String {
        let df = DateFormatter()
        df.dateFormat = withTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        df.timeZone = calendar.timeZone
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: d)
    }
}

/// "1h"、"1.5h"、"30m"、"2" → 小时
public enum Hours {
    public static func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return nil }
        if t.hasSuffix("min") { return Double(t.dropLast(3)).map { $0 / 60 } }
        if t.hasSuffix("m") { return Double(t.dropLast()).map { $0 / 60 } }
        if t.hasSuffix("h") { return Double(t.dropLast()) }
        return Double(t)
    }
}
