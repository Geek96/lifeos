import SwiftUI
import LifeOSCore

/// 月视图：每格一天，底色按负荷轻重，列出前几件事；双击某天进入那一周。
struct MonthView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let month = cal.dateInterval(of: .month, for: model.anchor) ?? model.weekRange
        let gridStart = cal.dateInterval(of: .weekOfYear, for: month.start)?.start ?? month.start
        let days = (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
        let range = DateInterval(start: gridStart, end: cal.date(byAdding: .day, value: 42, to: gridStart) ?? gridStart)
        let all = model.occurrences(in: range).filter { $0.style != .classSession }
        let loads = model.loads(for: range)

        VStack(spacing: 0) {
            HStack {
                Text(Fmt.string(month.start, "yyyy年M月")).font(.title2.bold())
                Spacer()
                Legend()
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Fmt.string(days[i], "EEE")).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(0..<6, id: \.self) { row in
                    GridRow {
                        ForEach(0..<7, id: \.self) { col in
                            let day = days[row * 7 + col]
                            DayCell(day: day,
                                    inMonth: cal.isDate(day, equalTo: month.start, toGranularity: .month),
                                    items: all.filter { $0.touches(day: day, calendar: cal) },
                                    load: loads[day])
                        }
                    }
                }
            }
            .background(.separator.opacity(0.5))
        }
    }
}

struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let inMonth: Bool
    let items: [Occurrence]
    let load: DayLoad?

    var body: some View {
        let today = model.calendar.isDate(day, inSameDayAs: model.clock)
        let level = load?.level ?? .light
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(Fmt.string(day, "d"))
                    .font(.callout.weight(today ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(today ? Color.white : inMonth ? Color.primary : Color.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(today ? Theme.red : .clear, in: Capsule())
                Spacer()
                if load != nil { LoadBadge(load: load, compact: true) }
            }
            ForEach(items.prefix(4)) { o in Chip(occurrence: o) }
            if items.count > 4 {
                Text("还有 \(items.count - 4) 项").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(level == .busy ? Theme.orange.opacity(0.06) : Color.clear)
        .background(.background)
        .opacity(inMonth ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.anchor = day; model.page = .week }
        .help("双击进入这一周")
    }
}
