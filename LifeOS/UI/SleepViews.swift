import SwiftUI
import Charts
import LifeOSCore

// 健康页的“睡眠”分页：只显示睡了多久、几点睡几点起，不打分、不评价。

struct SleepPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let today = model.clock
        let nights = model.health.sleep
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if nights.isEmpty {
                Text("还没有睡眠记录。跟 agent 说一句（比如“昨晚 1 点睡，今天 9 点起”），它会记到 健康/睡眠/。")
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
