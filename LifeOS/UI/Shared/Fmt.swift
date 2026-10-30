import Foundation
import LifeOSCore

/// 日期时间文案（中文，和 CourseOS 一致的写法）
enum Fmt {
    static func string(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f.string(from: d)
    }

    static func time(_ d: Date) -> String { string(d, "H:mm") }
    static func day(_ d: Date) -> String { string(d, "M月d日 EEE") }
    static func shortDay(_ d: Date) -> String { string(d, "M月d日") }

    /// 相对日期：今天 / 明天 / 周五 / 10月20日
    static func relativeDay(_ d: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(d, inSameDayAs: now) { return "今天" }
        if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) { return "明天" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: d)).day ?? 99
        if days > 0 && days < 7 { return string(d, "EEE") }
        return shortDay(d)
    }

    /// 一次出现的时间说明
    static func when(_ o: Occurrence, now: Date, calendar: Calendar, includeDay: Bool = false) -> String {
        let dayPrefix = includeDay ? relativeDay(o.start, now: now, calendar: calendar) + " " : ""
        switch o.style {
        case .window:
            guard let end = o.end else { return shortDay(o.start) }
            return calendar.isDate(o.start, inSameDayAs: end) ? shortDay(o.start) : "\(shortDay(o.start))–\(shortDay(end))"
        case .deadline, .courseDue, .courseOptional:
            return o.allDay ? dayPrefix + "当天" : dayPrefix + "截止 " + time(o.start)
        default:
            if o.allDay { return dayPrefix + "全天" }
            if let end = o.end { return dayPrefix + "\(time(o.start))–\(time(end))" }
            return dayPrefix + time(o.start)
        }
    }

    static func hours(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h)) 小时" : String(format: "%.1f 小时", h)
    }
}
