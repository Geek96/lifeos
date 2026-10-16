import SwiftUI
import LifeOSCore

/// 今天：快到了 → 今天的安排（按时间）→ 正在进行的时间窗 → 接下来几天。
/// 没有完成率、没有逾期、没有“今天过得怎么样”。
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let day = model.anchor
        let isToday = model.calendar.isDate(day, inSameDayAs: model.clock)
        let range = model.dayRange(day)
        let all = model.occurrences(in: range)
        let windows = all.filter { $0.style == .window && !$0.done }
        let timeline = all.filter { $0.style != .window }
        let loads = model.loads(for: range)

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(alignment: .firstTextBaseline) {
                    Text(isToday ? "今天" : Fmt.relativeDay(day, now: model.clock, calendar: model.calendar))
                        .font(.largeTitle.bold())
                    Text(Fmt.day(day)).font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    LoadBadge(load: loads[model.calendar.startOfDay(for: day)])
                }

                if isToday && !model.upcoming.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.upcoming) { o in row(o, includeDay: true) }
                        }
                    } header: {
                        SectionTitle(text: "快到了", systemImage: "bell")
                    }
                }

                Section {
                    if timeline.isEmpty {
                        Text("这天没有安排。")
                            .foregroundStyle(.secondary).padding(.vertical, 6)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(timeline) { o in row(o) }
                        }
                    }
                } header: {
                    SectionTitle(text: "安排", systemImage: "clock")
                }

                if !windows.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(windows) { o in row(o) }
                        }
                    } header: {
                        SectionTitle(text: "这段时间内找空做", systemImage: "arrow.left.and.right")
                    }
                }

                NextDays(from: day)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ o: Occurrence, includeDay: Bool = false) -> some View {
        OccurrenceRow(occurrence: o, includeDay: includeDay)
            .padding(.horizontal, Theme.Space.s)
            .background(model.selected?.id == o.id ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            .onTapGesture { model.selected = o; model.showInspector = true }
            .onTapGesture(count: 2) { if let item = model.item(for: o) { model.edit(item) } }
    }
}

struct SectionTitle: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.secondary)
            .padding(.bottom, 2)
    }
}

/// 接下来 6 天：每天一行，负荷 + 最多 3 件事的标题，点一下跳到周视图
struct NextDays: View {
    @Environment(AppModel.self) private var model
    let from: Date

    var body: some View {
        let cal = model.calendar
        let start = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from)) ?? from
        let range = DateInterval(start: start, duration: 6 * 86400)
        let all = model.occurrences(in: range).filter { $0.style != .classSession && $0.style != .window }
        let loads = model.loads(for: range)
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "接下来几天", systemImage: "calendar")
            ForEach(0..<6, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start) ?? start
                let things = all.filter { cal.isDate($0.start, inSameDayAs: day) }
                Button {
                    model.anchor = day
                    model.page = .week
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(Fmt.string(day, "EEE d日"))
                            .monospacedDigit()
                            .frame(width: 70, alignment: .leading)
                        LoadBadge(load: loads[day], compact: true)
                        Text(things.isEmpty ? "—" : things.prefix(3).map(\.title).joined(separator: " · ")
                             + (things.count > 3 ? " 等 \(things.count) 项" : ""))
                            .foregroundStyle(things.isEmpty ? .tertiary : .secondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
    }
}
