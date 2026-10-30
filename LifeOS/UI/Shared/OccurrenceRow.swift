import SwiftUI
import LifeOSCore

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
