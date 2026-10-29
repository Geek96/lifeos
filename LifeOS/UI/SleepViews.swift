import SwiftUI
import Charts
import LifeOSCore

// 休息与放松页：日（记一晚、那一晚睡了多久）/ 周、月（平均时长、平均几点睡几点起、每晚的睡眠时段、月历热力格、
// 和训练、考试放在一起看）。
// 只陈述，不打分、不评价、不提醒。

struct RestView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("restScale") private var scale = HealthPeriod.Scale.week.rawValue
    @State private var anchor = Date()

    var body: some View {
        let period = HealthPeriod(scale: HealthPeriod.Scale(rawValue: scale) ?? .week, anchor: anchor)
        HealthPageScaffold(title: "休息与放松") {
            HealthPeriodBar(period: Binding(get: { period }, set: { scale = $0.scale.rawValue; anchor = $0.anchor }))
            switch period.scale {
            case .day:
                SleepEntryForm(day: $anchor)
                RestDayPage(day: anchor)
            case .week, .month:
                SleepEntryForm(day: nil)
                RestRangePage(period: period) { d in anchor = d; scale = HealthPeriod.Scale.day.rawValue }
            }
        }
    }
}

/// 记一晚：起床那天 + 入睡 + 起床（可以只填一个）。选到已经记过的那天就带出原来的时间，再记一次是改。
/// 在“日”里日期跟着页面走；在“周 / 月”里自己选，默认今天。
struct SleepEntryForm: View {
    @Environment(AppModel.self) private var model
    @State private var ownDay = Date()
    @State private var bedtime = ""
    @State private var wake = ""
    private let external: Binding<Date>?

    init(day: Binding<Date>?) { external = day }

    private var day: Binding<Date> { external ?? $ownDay }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "记一晚", systemImage: "bed.double")
            // 窄了就把日期和两个时间分成两行
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) {
                    datePicker
                    fields
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    datePicker
                    fields
                }
            }
            Text("日期写起床那天；只记得一个就只填一个。").font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.l)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .onAppear(perform: fill)
        .onChange(of: day.wrappedValue) { fill() }
    }

    private var datePicker: some View {
        DatePicker("起床那天", selection: day, in: ...model.clock, displayedComponents: .date)
            .fixedSize()
    }

    private var fields: some View {
        let existing = model.health.sleep(on: day.wrappedValue, calendar: model.calendar)
        return HStack(spacing: Theme.Space.m) {
            TextField("入睡，比如 23:40", text: $bedtime)
                .textFieldStyle(.roundedBorder).frame(width: 130)
                .onSubmit(save)
            TextField("起床，比如 07:30", text: $wake)
                .textFieldStyle(.roundedBorder).frame(width: 130)
                .onSubmit(save)
            Button(existing == nil ? "记下" : "更新", action: save)
                .disabled(bedtime.trimmingCharacters(in: .whitespaces).isEmpty
                          && wake.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .fixedSize()
    }

    /// 这天已经记过：带出原来的时间
    private func fill() {
        let n = model.health.sleep(on: day.wrappedValue, calendar: model.calendar)
        bedtime = n?.bedtime ?? ""
        wake = n?.wake ?? ""
    }

    private func save() {
        if model.recordSleep(wakeDay: day.wrappedValue, bedtime: bedtime, wake: wake) { fill() }
    }
}

/// 休息 · 日：那一晚
struct RestDayPage: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let cal = model.calendar
        let night = model.health.sleep(on: day, calendar: cal)
        let week = HealthPeriod(scale: .week, anchor: day)
        let avg = model.health.sleepSummary(in: week.interval(calendar: cal)).averageMinutes
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if let night {
                StatRow {
                    StatTile(title: "睡了", value: night.minutes.map(HealthFormat.sleepText) ?? "—")
                    StatTile(title: "入睡", value: night.bedtime ?? "—")
                    StatTile(title: "起床", value: night.wake ?? "—")
                    StatTile(title: "这周平均", value: avg.map(HealthFormat.sleepText) ?? "—")
                }
            } else {
                Text("这天早上还没有睡眠记录。").foregroundStyle(.secondary)
            }
        }
    }
}

/// 休息 · 周 / 月
struct RestRangePage: View {
    @Environment(AppModel.self) private var model
    let period: HealthPeriod
    let onSelectDay: (Date) -> Void

    private struct Window: Identifiable {
        var id: Date { day }
        var day: Date
        var bed: Double
        var wake: Double
    }

    var body: some View {
        let cal = model.calendar
        let days = period.days(calendar: cal)
        let summary = model.health.sleepSummary(in: period.interval(calendar: cal))
        let windows: [Window] = summary.nights.compactMap { n in
            guard let b = n.bedtime.flatMap(HealthSnapshot.bedtimeHour), let w = n.wake.flatMap(HealthSnapshot.wakeHour), w > b else { return nil }
            return Window(day: n.date, bed: b, wake: w)
        }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            StatRow {
                StatTile(title: "平均睡了", value: summary.averageMinutes.map(HealthFormat.sleepText) ?? "—")
                StatTile(title: "平均入睡", value: summary.averageBedtime ?? "—")
                StatTile(title: "平均起床", value: summary.averageWake ?? "—")
                StatTile(title: "记了", value: "\(summary.nights.count) / \(days.count) 晚")
            }

            if period.scale == .month {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "每晚睡了多久", systemImage: "square.grid.3x3")
                    MonthHeatGrid(days: days, color: Theme.indigo, cell: heat, onSelect: onSelectDay)
                    Text("颜色越深睡得越久（按 9 小时算满）；灰 = 没记。点一天看那天。").font(.caption).foregroundStyle(.secondary)
                }
            }

            if !windows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: "几点睡、几点起", systemImage: "moon.zzz")
                    Chart(windows) { w in
                        BarMark(x: .value("日期", w.day, unit: .day), yStart: .value("入睡", w.bed), yEnd: .value("起床", w.wake))
                            .foregroundStyle(Theme.indigo.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                    .chartYAxis {
                        AxisMarks { v in
                            AxisGridLine()
                            AxisValueLabel { if let h = v.as(Double.self) { Text(String(format: "%02d:00", Int(h) % 24)) } }
                        }
                    }
                    .chartXAxis { xAxis }
                    .frame(height: 180)
                    Text("每根柱子从入睡画到起床，越往下越晚。").font(.caption).foregroundStyle(.secondary)
                }
            }

            DailyBarChart(title: "睡了多久（小时）", points: days.map { d in
                .init(day: d, value: (model.health.sleep(on: d, calendar: cal)?.minutes ?? 0) / 60)
            }, color: Theme.indigo, axisLabel: { "\(Int($0)) h" })

            SleepContextSection(period: period, nights: summary.nights)

            if !summary.nights.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "记录", systemImage: "list.bullet")
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow { Text("起床那天"); Text("入睡"); Text("起床"); Text("时长") }
                            .font(.caption).foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(summary.nights.reversed()) { n in
                            GridRow {
                                Text(Fmt.string(n.date, "M月d日 EEE")).foregroundStyle(.secondary)
                                Text(n.bedtime ?? "—")
                                Text(n.wake ?? "—")
                                Text(n.minutes.map(HealthFormat.sleepText) ?? "—")
                            }
                            .monospacedDigit()
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectDay(n.date) }
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }

    @AxisContentBuilder private var xAxis: some AxisContent {
        if period.scale == .month {
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.day()) }
        } else {
            AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
        }
    }

    private func heat(_ d: Date) -> HeatCell {
        guard let n = model.health.sleep(on: d, calendar: model.calendar) else { return HeatCell() }
        guard let m = n.minutes else { return HeatCell(fraction: nil, text: n.wake ?? n.bedtime) }
        return HeatCell(fraction: m / 540, text: String(format: "%.1fh", m / 60))
    }
}

/// 睡眠和训练、考试放在一起看：哪天练了、哪天考试标在同一条时间轴上，再把睡眠按“练没练”“考试前一晚”分开平均。
/// 只陈述，不下结论、不打分。
struct SleepContextSection: View {
    @Environment(AppModel.self) private var model
    let period: HealthPeriod
    let nights: [SleepNight]

    private struct Mark: Identifiable {
        var id: String { kind + "\(day.timeIntervalSince1970)" }
        var day: Date
        var kind: String
    }

    var body: some View {
        let cal = model.calendar
        let iv = period.interval(calendar: cal)
        // 多看前一天：这段时间第一晚的“前一天练没练”也要知道
        let wide = DateInterval(start: cal.date(byAdding: .day, value: -1, to: iv.start) ?? iv.start, end: iv.end)
        let training = Set(model.health.sessions.filter { wide.containsHalfOpen($0.date) }.map { cal.startOfDay(for: $0.date) })
        let exams = model.examDays(in: iv)
        let cmp = SleepComparison.compute(nights, trainingDays: training, examDays: exams, calendar: cal)
        let marks = training.filter { iv.containsHalfOpen($0) }.map { Mark(day: $0, kind: "训练") }
            + exams.map { Mark(day: $0, kind: "考试") }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(text: "和训练、考试放在一起看", systemImage: "square.stack.3d.up")
            if marks.isEmpty {
                Text("这段时间没有训练记录，也没有考试。").foregroundStyle(.secondary)
            } else {
                Chart(marks) { m in
                    PointMark(x: .value("日期", m.day, unit: .day), y: .value("类型", m.kind))
                        .symbol(m.kind == "考试" ? .diamond : .circle)
                        .symbolSize(90)
                        .foregroundStyle(m.kind == "考试" ? Theme.red : Theme.green)
                }
                .chartXScale(domain: iv.start...iv.end)
                .chartYScale(domain: ["训练", "考试"])
                .chartXAxis {
                    if period.scale == .month {
                        AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.day()) }
                    } else {
                        AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                    }
                }
                .frame(height: 70)
            }
            StatRow {
                StatTile(title: "练了那天晚上", value: text(cmp.afterTraining, cmp.afterTrainingCount))
                StatTile(title: "没练的晚上", value: text(cmp.afterRest, cmp.afterRestCount))
                StatTile(title: "考试前一晚", value: text(cmp.beforeExam, cmp.beforeExamCount))
            }
            Text("睡眠记在起床那天：练了那天晚上的睡眠，算在第二天早上那一晚；考试前一晚 = 考试那天早上起床的那一晚。训练按训练记录算，考试来自 CourseOS。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func text(_ minutes: Double?, _ n: Int) -> String {
        guard let minutes else { return "—" }
        return HealthFormat.sleepText(minutes) + "（\(n) 晚）"
    }
}
