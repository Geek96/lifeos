import SwiftUI
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

/// 列表里的一行：色条 + 图标 + 标题/副标题 + 右侧时间。过去的淡出，不标红。
struct OccurrenceRow: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    var includeDay = false

    var body: some View {
        let o = occurrence
        let past = o.isPast(now: model.clock)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.tint(o.style))
                .frame(width: 4, height: 30)
            Image(systemName: Theme.icon(o.style))
                .foregroundStyle(Theme.tint(o.style))
                .frame(width: 18)
                .accessibilityLabel(o.style.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.title)
                    .strikethrough(o.done)
                    .lineLimit(1)
                if !o.subtitle.isEmpty {
                    Text(o.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(Fmt.when(o, now: model.clock, calendar: model.calendar, includeDay: includeDay))
                .font(.callout).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(past || o.done ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 负荷标记：色点 + 文字（颜色从不单独表达含义）
struct LoadBadge: View {
    let load: DayLoad?
    var compact = false

    var body: some View {
        let level = load?.level ?? .light
        HStack(spacing: 4) {
            Circle().fill(Theme.load(level)).frame(width: 6, height: 6)
            if !compact { Text(level.label) }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(load.map { "上课 \(Fmt.hours($0.classHours)) · 约定 \(Fmt.hours($0.eventHours)) · 课业约 \(Fmt.hours($0.courseworkHours))" } ?? "没有安排")
        .accessibilityLabel("这天\(level.label)")
    }
}
