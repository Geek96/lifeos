import Foundation

/// 一天有多满：上课 + 约定 + 课业（课程截止的预估工作量摊到截止前几天）。
public struct DayLoad: Sendable, Equatable {
    public enum Level: Int, Sendable, Comparable {
        case light, normal, busy
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        public var label: String {
            switch self { case .light: return "轻松"; case .normal: return "一般"; case .busy: return "很满" }
        }
    }

    public var classHours: Double = 0
    public var eventHours: Double = 0
    public var courseworkHours: Double = 0

    public var total: Double { classHours + eventHours + courseworkHours }

    public var level: Level {
        total < 3 ? .light : total < 6.5 ? .normal : .busy
    }

    public init(classHours: Double = 0, eventHours: Double = 0, courseworkHours: Double = 0) {
        self.classHours = classHours
        self.eventHours = eventHours
        self.courseworkHours = courseworkHours
    }
}

/// 给用户的轻提示（不拦、不催）
public struct Hint: Hashable, Sendable {
    public enum Tone: Sendable { case info, caution }
    public var text: String
    public var tone: Tone
}

/// 推荐的空档
public struct FreeSlot: Hashable, Sendable {
    public var interval: DateInterval
    public var load: Double
}

public enum Insights {
    // MARK: - 负荷

    /// 按天（startOfDay）汇总负荷。occurrences 应覆盖目标日期之后几天（课业摊到截止前）。
    public static func loads(_ occurrences: [Occurrence], calendar: Calendar = .current) -> [Date: DayLoad] {
        var result: [Date: DayLoad] = [:]
        for o in occurrences {
            let day = calendar.startOfDay(for: o.start)
            switch o.style {
            case .classSession:
                result[day, default: .init()].classHours += hours(o)
            case .event:
                if !o.allDay { result[day, default: .init()].eventHours += hours(o) }
            case .courseDue, .courseExam:
                guard !o.done, let w = o.workloadHours, w > 0 else { continue }
                for (d, h) in spread(hours: w, due: o.start, calendar: calendar) {
                    result[d, default: .init()].courseworkHours += h
                }
            default:
                continue
            }
        }
        return result
    }

    /// 工作量摊到截止前的几天：每天最多约 3 小时、最多 4 天；中午前截止的不算当天。
    static func spread(hours: Double, due: Date, calendar: Calendar) -> [(Date, Double)] {
        let n = min(4, max(1, Int((hours / 3).rounded(.up))))
        let dueDay = calendar.startOfDay(for: due)
        let lastDay = calendar.component(.hour, from: due) >= 12 ? dueDay
            : (calendar.date(byAdding: .day, value: -1, to: dueDay) ?? dueDay)
        return (0..<n).compactMap { i in
            calendar.date(byAdding: .day, value: -i, to: lastDay).map { ($0, hours / Double(n)) }
        }
    }

    static func hours(_ o: Occurrence) -> Double {
        guard let b = o.timedBlock else { return 0 }
        return b.duration / 3600
    }

    // MARK: - 提示

    /// 某个生活事项的提示：时间重叠、考试前夜/当天、课业很满的一天。
    public static func hints(for target: Occurrence, among all: [Occurrence], loads: [Date: DayLoad],
                             calendar: Calendar = .current) -> [Hint] {
        var hints: [Hint] = []
        let day = calendar.startOfDay(for: target.start)
        if let block = target.timedBlock {
            for o in all where o.id != target.id {
                guard let b = o.timedBlock, b.intersects(block), b.end > block.start, b.start < block.end else { continue }
                hints.append(Hint(text: "和「\(o.title)」时间重叠（\(clock(b.start, calendar))–\(clock(b.end, calendar))）", tone: .caution))
            }
        }
        if !target.style.isCourse {
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            for o in all where o.style == .courseExam && !o.done {
                let examDay = calendar.startOfDay(for: o.start)
                if examDay == day {
                    hints.append(Hint(text: "当天有考试：\(o.subtitle) \(o.title)", tone: .caution))
                } else if examDay == tomorrow, calendar.component(.hour, from: target.start) >= 18 || target.allDay {
                    hints.append(Hint(text: "第二天有考试：\(o.subtitle) \(o.title)", tone: .caution))
                }
            }
            if let load = loads[day], load.level == .busy {
                hints.append(Hint(text: "这天已经比较满（约 \(Int(load.total.rounded())) 小时：上课、约定和课业）", tone: .info))
            }
        }
        return hints
    }

    // MARK: - 找空档

    /// 在 [from, until] 的每天 dayStart–dayEnd 时段里找不和任何时间块重叠、长度 ≥ hours 的空档，
    /// 按“那天负荷轻 → 早”排序，返回前 limit 个（每天最多一个）。
    public static func freeSlots(from: Date, until: Date, hours: Double, among all: [Occurrence],
                                 loads: [Date: DayLoad], dayStart: Int = 9, dayEnd: Int = 21,
                                 limit: Int = 3, calendar: Calendar = .current) -> [FreeSlot] {
        let need = max(hours, 0.25) * 3600
        let blocks = all.compactMap(\.timedBlock).sorted { $0.start < $1.start }
        var candidates: [FreeSlot] = []
        var day = calendar.startOfDay(for: from)
        var guardCount = 0
        while day <= until, guardCount < 120 {
            guardCount += 1
            defer { day = calendar.date(byAdding: .day, value: 1, to: day) ?? until.addingTimeInterval(1) }
            guard let open = calendar.date(bySettingHour: dayStart, minute: 0, second: 0, of: day),
                  let close = calendar.date(bySettingHour: dayEnd, minute: 0, second: 0, of: day) else { continue }
            var cursor = max(open, roundUp(from, calendar))
            for b in blocks where b.end > cursor && b.start < close {
                if b.start.timeIntervalSince(cursor) >= need { break }
                cursor = max(cursor, b.end)
            }
            if close.timeIntervalSince(cursor) >= need {
                candidates.append(FreeSlot(interval: DateInterval(start: cursor, duration: need),
                                           load: loads[day]?.total ?? 0))
            }
        }
        return Array(candidates.sorted { ($0.load, $0.interval.start) < ($1.load, $1.interval.start) }.prefix(limit))
    }

    /// 取整到下一个半点
    static func roundUp(_ d: Date, _ calendar: Calendar) -> Date {
        let m = calendar.component(.minute, from: d)
        let add = m == 0 || m == 30 ? 0 : (m < 30 ? 30 - m : 60 - m)
        let r = calendar.date(byAdding: .minute, value: add, to: d) ?? d
        return calendar.date(bySetting: .second, value: 0, of: r) ?? r
    }

    static func clock(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: - 快到了

    /// 顶部“快到了”：remindDays 内的未办期限、2 天内结束的未办时间窗。
    public static func upcoming(_ items: [LifeItem], now: Date, calendar: Calendar = .current) -> [Occurrence] {
        let horizon = DateInterval(start: calendar.startOfDay(for: now), duration: 40 * 86400)
        return items.filter { !$0.done && $0.kind != .event }.flatMap {
            Recurrence.occurrences(of: $0, in: horizon, calendar: calendar).prefix(1)
        }.filter { o in
            guard let item = items.first(where: { $0.id == o.itemID }) else { return false }
            let target = o.style == .window ? (o.end ?? o.start) : o.start
            guard target >= now else { return false }
            if o.style == .window, o.start > now { return false }
            let days = o.style == .window ? 2 : item.remindDays
            return target.timeIntervalSince(now) <= Double(days) * 86400
        }.sorted { ($0.end ?? $0.start) < ($1.end ?? $1.start) }
    }
}
