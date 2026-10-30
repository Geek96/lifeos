import SwiftUI
import LifeOSCore

/// 日历：上面月历（每天的点按负荷着色、有事的日子下面一个小点），下面是选中那天（或那一周）的安排
struct PhoneCalendarView: View {
    @Environment(PhoneModel.self) private var model
    @State private var selected = Date()
    @State private var scale: Scale = .day

    enum Scale: String, CaseIterable { case day = "这天", week = "这周" }

    var body: some View {
        let cal = model.calendar
        NavigationStack {
            List {
                Section {
                    MonthGrid(selected: $selected)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    Picker("范围", selection: $scale) {
                        ForEach(Scale.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
                switch scale {
                case .day:
                    daySection(selected, title: Fmt.day(selected))
                case .week:
                    let week = cal.dateInterval(of: .weekOfYear, for: selected) ?? model.dayRange(selected)
                    ForEach(0..<7, id: \.self) { i in
                        let d = cal.date(byAdding: .day, value: i, to: week.start) ?? week.start
                        daySection(d, title: Fmt.day(d), hideEmpty: false)
                    }
                }
            }
            .navigationTitle(Fmt.string(selected, "yyyy年M月"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") { selected = model.clock }
                }
                ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            }
            .refreshable { model.reload() }
        }
    }

    @ViewBuilder
    private func daySection(_ day: Date, title: String, hideEmpty: Bool = false) -> some View {
        let items = model.occurrences(in: model.dayRange(day))
        Section {
            if items.isEmpty {
                Text("没有安排").foregroundStyle(.tertiary)
            } else {
                ForEach(items) { PhoneOccurrenceRow(occurrence: $0) }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                PhoneLoadBadge(load: model.loads(for: model.dayRange(day))[model.calendar.startOfDay(for: day)])
            }
        }
    }
}

/// 月历格子：左右滑或点箭头换月，点某天选中
struct MonthGrid: View {
    @Environment(PhoneModel.self) private var model
    @Binding var selected: Date

    var body: some View {
        let cal = model.calendar
        let month = cal.dateInterval(of: .month, for: selected) ?? model.dayRange(selected)
        let gridStart = cal.dateInterval(of: .weekOfYear, for: month.start)?.start ?? month.start
        let weeks = Int(ceil(Double(cal.dateComponents([.day], from: gridStart, to: month.end).day ?? 35) / 7))
        let days = (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
        let range = DateInterval(start: gridStart, end: cal.date(byAdding: .day, value: weeks * 7, to: gridStart) ?? gridStart)
        let all = model.occurrences(in: range).filter { $0.style != .classSession }
        let loads = model.loads(for: range)

        VStack(spacing: 6) {
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上个月")
                Spacer()
                Text(Fmt.string(month.start, "M月")).font(.headline)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("下个月")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Fmt.string(days[i], "EEEEE")).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let has = all.contains { $0.touches(day: day, calendar: cal) }
                    let exam = all.contains { $0.style == .courseExam && cal.isDate($0.start, inSameDayAs: day) }
                    DayDot(day: day,
                           inMonth: cal.isDate(day, equalTo: month.start, toGranularity: .month),
                           isSelected: cal.isDate(day, inSameDayAs: selected),
                           isToday: cal.isDate(day, inSameDayAs: model.clock),
                           hasItems: has, hasExam: exam, load: loads[day])
                        .onTapGesture { selected = day }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > abs(v.translation.height) { step(v.translation.width < 0 ? 1 : -1) }
        })
    }

    private func step(_ n: Int) {
        selected = model.calendar.date(byAdding: .month, value: n, to: selected) ?? selected
    }
}

struct DayDot: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let hasItems: Bool
    let hasExam: Bool
    let load: DayLoad?

    var body: some View {
        VStack(spacing: 2) {
            Text(Fmt.string(day, "d"))
                .font(.callout.weight(isToday ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : isToday ? Theme.red : inMonth ? Color.primary : Color.secondary)
                .frame(width: 32, height: 32)
                .background(isSelected ? Theme.red : (load?.level == .busy ? Theme.orange.opacity(0.12) : .clear), in: Circle())
            HStack(spacing: 2) {
                Circle().fill(hasItems ? Color.secondary : .clear).frame(width: 4, height: 4)
                if hasExam { Circle().fill(Theme.purple).frame(width: 4, height: 4) }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .opacity(inMonth ? 1 : 0.45)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Fmt.day(day) + (hasExam ? "，有考试" : hasItems ? "，有安排" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
