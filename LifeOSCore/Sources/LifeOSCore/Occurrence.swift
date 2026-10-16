import Foundation

/// 日历上的一次出现：生活事项（重复事项展开成多次）、课程上课、课程截止/考试都统一成这个。
public struct Occurrence: Identifiable, Hashable, Sendable {
    public enum Style: String, Sendable, CaseIterable {
        case event, deadline, window
        /// CourseOS：上课时间块
        case classSession
        /// CourseOS：要交的（作业、阅读、测验）
        case courseDue
        /// CourseOS：考试
        case courseExam
        /// CourseOS：可选活动、通知
        case courseOptional

        public var isCourse: Bool { self == .classSession || self == .courseDue || self == .courseExam || self == .courseOptional }

        public var label: String {
            switch self {
            case .event: return "约定"
            case .deadline: return "期限"
            case .window: return "时间窗"
            case .classSession: return "上课"
            case .courseDue: return "课程截止"
            case .courseExam: return "考试"
            case .courseOptional: return "课程活动"
            }
        }
    }

    public var id: String
    public var style: Style
    public var title: String
    /// 课号或地点
    public var subtitle: String
    public var start: Date
    /// 有时长的块才有；deadline / 课程截止为 nil
    public var end: Date?
    public var allDay: Bool
    public var done: Bool
    /// 生活事项的文件路径（课程图层为 nil）
    public var itemID: String?
    /// 课程图层：CourseOS 待办表的 id / 课号
    public var courseItemID: String?
    public var course: String?
    public var workloadHours: Double?
    public var sourceURL: URL?
    public var location: String

    public init(id: String, style: Style, title: String, subtitle: String = "", start: Date, end: Date? = nil,
                allDay: Bool = false, done: Bool = false, itemID: String? = nil, courseItemID: String? = nil,
                course: String? = nil, workloadHours: Double? = nil, sourceURL: URL? = nil, location: String = "") {
        self.id = id
        self.style = style
        self.title = title
        self.subtitle = subtitle
        self.start = start
        self.end = end
        self.allDay = allDay
        self.done = done
        self.itemID = itemID
        self.courseItemID = courseItemID
        self.course = course
        self.workloadHours = workloadHours
        self.sourceURL = sourceURL
        self.location = location
    }

    /// 占用时间的块（能和别的块冲突）：约定、上课、考试（有结束时间或带具体时刻的考试按 2 小时算）
    public var timedBlock: DateInterval? {
        if allDay { return nil }
        switch style {
        case .event, .classSession:
            return DateInterval(start: start, end: max(end ?? start.addingTimeInterval(3600), start))
        case .courseExam:
            return DateInterval(start: start, end: max(end ?? start.addingTimeInterval(2 * 3600), start))
        default:
            return nil
        }
    }

    /// 已经过去（淡出）：块看结束，点看时刻，窗口看结束日
    public func isPast(now: Date) -> Bool {
        (end ?? start) < now
    }

    /// 是否落在某天（窗口跨天时每天都算）
    public func touches(day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let e = end ?? start
        return start < dayEnd && e >= dayStart
    }
}

/// 把生活事项展开成某个时间段内的出现（重复规则在这里展开）。
public enum Recurrence {
    public static func occurrences(of item: LifeItem, in range: DateInterval, calendar: Calendar = .current) -> [Occurrence] {
        starts(of: item, in: range, calendar: calendar).map { s in
            let shift = s.timeIntervalSince(item.start)
            let end: Date? = {
                switch item.kind {
                case .event: return s.addingTimeInterval(item.duration)
                case .window: return item.end.map { $0.addingTimeInterval(shift) } ?? endOfDay(s, calendar)
                case .deadline: return nil
                }
            }()
            let style: Occurrence.Style = item.kind == .event ? .event : item.kind == .deadline ? .deadline : .window
            return Occurrence(
                id: item.repeatRule == nil ? item.id : item.id + "@" + DateText.format(s, withTime: false, calendar: calendar),
                style: style, title: item.title, subtitle: item.location,
                start: s, end: end, allDay: item.kind == .window || (item.kind == .event && item.allDay),
                done: item.done, itemID: item.id, location: item.location)
        }
    }

    /// 某个事项在区间内的所有开始时刻（不重复的事项：只要和区间有交集就返回它自己）
    static func starts(of item: LifeItem, in range: DateInterval, calendar: Calendar) -> [Date] {
        let span = item.kind == .window ? (item.end ?? item.start).timeIntervalSince(item.start) : item.duration
        guard let rule = item.repeatRule else {
            let e = item.kind == .deadline ? item.start : item.start.addingTimeInterval(max(span, 0))
            return (item.start < range.end && e >= range.start) ? [item.start] : []
        }
        var result: [Date] = []
        let until = item.repeatUntil.map { endOfDay($0, calendar) } ?? .distantFuture
        // 从事项开始那天起逐日检查（区间之前的跳过），最多覆盖到区间结束
        var day = calendar.startOfDay(for: max(item.start, range.start.addingTimeInterval(-max(span, 0))))
        if day < calendar.startOfDay(for: item.start) { day = calendar.startOfDay(for: item.start) }
        let time = calendar.dateComponents([.hour, .minute], from: item.start)
        let startDay = calendar.dateComponents([.month, .day, .weekday], from: item.start)
        var guardCount = 0
        while day < range.end, day <= until, guardCount < 800 {
            guardCount += 1
            let c = calendar.dateComponents([.month, .day, .weekday], from: day)
            let hit: Bool
            switch rule {
            case .daily: hit = true
            case .weekly(let days): hit = (days.isEmpty ? [startDay.weekday ?? 0] : days).contains(c.weekday ?? -1)
            case .monthly(let d):
                let target = d > 0 ? d : (startDay.day ?? 1)
                let lastDay = calendar.range(of: .day, in: .month, for: day)?.count ?? 28
                hit = c.day == min(target, lastDay)
            case .yearly: hit = c.month == startDay.month && c.day == startDay.day
            }
            if hit, let s = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day),
               s >= item.start, s <= until {
                let e = s.addingTimeInterval(max(span, 0))
                if s < range.end && e >= range.start { result.append(s) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    static func endOfDay(_ d: Date, _ calendar: Calendar) -> Date {
        (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: d)) ?? d).addingTimeInterval(-1)
    }
}
