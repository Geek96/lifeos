import SwiftUI
import Charts
import LifeOSCore

// 休息睡眠与心理健康页：记一晚 + 睡了多久、几点睡几点起。只陈述，不打分、不评价、不提醒。
// 心理健康的部分还没做（格式要先和用户商量），现在这页只有睡眠。

struct RestView: View {
    var body: some View {
        HealthPageScaffold(title: "休息睡眠与心理健康") {
            SleepEntryForm()
            SleepPage()
        }
    }
}

/// 记一晚：起床那天 + 入睡 + 起床（可以只填一个）。选到已经记过的那天就带出原来的时间，再记一次是改。
struct SleepEntryForm: View {
    @Environment(AppModel.self) private var model
    @State private var day = Date()
    @State private var bedtime = ""
    @State private var wake = ""

    var body: some View {
        let existing = model.health.sleep(on: day, calendar: model.calendar)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "记一晚", systemImage: "bed.double")
            HStack(spacing: Theme.Space.m) {
                DatePicker("起床那天", selection: $day, in: ...model.clock, displayedComponents: .date)
                    .fixedSize()
                TextField("入睡，比如 23:40", text: $bedtime)
                    .textFieldStyle(.roundedBorder).frame(width: 130)
                    .onSubmit(save)
                TextField("起床，比如 07:30", text: $wake)
                    .textFieldStyle(.roundedBorder).frame(width: 130)
                    .onSubmit(save)
                Button(existing == nil ? "记下" : "更新", action: save)
                    .disabled(bedtime.trimmingCharacters(in: .whitespaces).isEmpty
                              && wake.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            Text("日期写起床那天；只记得一个就只填一个。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.l)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        .onAppear(perform: fill)
        .onChange(of: day) { fill() }
    }

    /// 这天已经记过：带出原来的时间
    private func fill() {
        let n = model.health.sleep(on: day, calendar: model.calendar)
        bedtime = n?.bedtime ?? ""
        wake = n?.wake ?? ""
    }

    private func save() {
        if model.recordSleep(wakeDay: day, bedtime: bedtime, wake: wake) { fill() }
    }
}

struct SleepPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let today = model.clock
        let nights = model.health.sleep
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if nights.isEmpty {
                Text("还没有睡眠记录。在上面记一晚，或者跟 agent 说一句（比如“昨晚 1 点睡，今天 9 点起”），都会记到 健康/睡眠/。")
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: Theme.Space.m) {
                    StatTile(title: "昨晚睡了", value: model.health.sleep(on: today, calendar: cal)?.minutes
                        .map(HealthFormat.sleepText) ?? "—")
                    StatTile(title: "近 7 天平均", value: model.health.averageSleep(days: 7, until: today, calendar: cal)
                        .map(HealthFormat.sleepText) ?? "—")
                    StatTile(title: "近 30 天平均", value: model.health.averageSleep(days: 30, until: today, calendar: cal)
                        .map(HealthFormat.sleepText) ?? "—")
                }

                let recent = nights.filter { n in
                    guard let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: today)) else { return false }
                    return n.date >= start && n.minutes != nil
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionTitle(text: "最近 14 晚", systemImage: "chart.bar")
                        Chart(recent) { n in
                            BarMark(x: .value("日期", n.date, unit: .day), y: .value("小时", (n.minutes ?? 0) / 60))
                                .foregroundStyle(Theme.indigo.gradient)
                        }
                        .chartYAxis {
                            AxisMarks { v in
                                AxisGridLine()
                                AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h)) h") } }
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 2)) { _ in
                                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                            }
                        }
                        .frame(height: 150)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "记录", systemImage: "moon.zzz")
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                        GridRow { Text("起床那天"); Text("入睡"); Text("起床"); Text("时长") }
                            .font(.caption).foregroundStyle(.secondary)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(nights.reversed()) { n in
                            GridRow {
                                Text(Fmt.string(n.date, "M月d日 EEE")).foregroundStyle(.secondary)
                                Text(n.bedtime ?? "—")
                                Text(n.wake ?? "—")
                                Text(n.minutes.map(HealthFormat.sleepText) ?? "—")
                            }
                            .monospacedDigit()
                        }
                    }
                    .font(.callout)
                }
            }
        }
    }
}
