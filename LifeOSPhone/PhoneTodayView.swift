import SwiftUI
import LifeOSCore

/// 今天：营养小结 → 快到了 → 安排 → 这段时间内找空做 → 接下来几天。和电脑版一样，没有完成率和逾期。
struct PhoneTodayView: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let day = model.clock
        let range = model.dayRange(day)
        let all = model.occurrences(in: range)
        let windows = all.filter { $0.style == .window && !$0.done }
        let timeline = all.filter { $0.style != .window }
        let load = model.loads(for: range)[model.calendar.startOfDay(for: day)]

        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(Fmt.day(day)).foregroundStyle(.secondary)
                        Spacer()
                        PhoneLoadBadge(load: load)
                    }
                    if model.config.plugins.health {
                        NutritionMiniCard(day: day)
                    }
                }
                if !model.upcoming.isEmpty {
                    Section("快到了") {
                        ForEach(model.upcoming) { PhoneOccurrenceRow(occurrence: $0, includeDay: true) }
                    }
                }
                Section("安排") {
                    if timeline.isEmpty {
                        Text("今天没有安排。").foregroundStyle(.secondary)
                    } else {
                        ForEach(timeline) { PhoneOccurrenceRow(occurrence: $0) }
                    }
                }
                if !windows.isEmpty {
                    Section("这段时间内找空做") {
                        ForEach(windows) { PhoneOccurrenceRow(occurrence: $0) }
                    }
                }
                PhoneNextDays(from: day)
            }
            .navigationTitle("今天")
            .toolbar { SettingsButton() }
            .refreshable { model.reload() }
        }
    }
}

/// 接下来 6 天：每天一行，负荷 + 最多 3 件事
struct PhoneNextDays: View {
    @Environment(PhoneModel.self) private var model
    let from: Date

    var body: some View {
        let cal = model.calendar
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from)) ?? from
        let range = DateInterval(start: start, duration: 6 * 86400)
        let all = model.occurrences(in: range).filter { $0.style != .classSession && $0.style != .window }
        let loads = model.loads(for: range)
        Section("接下来几天") {
            ForEach(0..<6, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start) ?? start
                let things = all.filter { cal.isDate($0.start, inSameDayAs: day) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Fmt.string(day, "EEE d日")).monospacedDigit().frame(width: 62, alignment: .leading)
                    PhoneLoadBadge(load: loads[day], compact: true)
                    Text(things.isEmpty ? "—" : things.prefix(3).map(\.title).joined(separator: " · ")
                         + (things.count > 3 ? " 等 \(things.count) 项" : ""))
                        .font(.callout)
                        .foregroundStyle(things.isEmpty ? .tertiary : .secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// 一行：色条 + 图标 + 标题 / 副标题 + 时间。过去的淡出，不标红
struct PhoneOccurrenceRow: View {
    @Environment(PhoneModel.self) private var model
    let occurrence: Occurrence
    var includeDay = false

    var body: some View {
        let o = occurrence
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.tint(o.style)).frame(width: 4, height: 32)
            Image(systemName: Theme.icon(o.style)).foregroundStyle(Theme.tint(o.style)).frame(width: 18)
                .accessibilityLabel(o.style.label)
            VStack(alignment: .leading, spacing: 2) {
                Text(o.title).strikethrough(o.done).lineLimit(2)
                if !o.subtitle.isEmpty {
                    Text(o.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Text(Fmt.when(o, now: model.clock, calendar: model.calendar, includeDay: includeDay))
                .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .opacity(o.isPast(now: model.clock) || o.done ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// 负荷：色点 + 文字（颜色不单独表达含义）
struct PhoneLoadBadge: View {
    let load: DayLoad?
    var compact = false

    var body: some View {
        let level = load?.level ?? .light
        HStack(spacing: 4) {
            Circle().fill(Theme.load(level)).frame(width: 7, height: 7)
            if !compact { Text(level.label) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("这天\(level.label)")
    }
}
