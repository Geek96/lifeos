import SwiftUI
import Charts
import LifeOSCore

// 健康三页共用：日 / 周 / 月 切换条、月历热力格、按天的柱状图。

/// 顶上一排：日 / 周 / 月 + 往前、今天、往后 + 现在看的是哪一段
struct HealthPeriodBar: View {
    @Environment(AppModel.self) private var model
    @Binding var period: HealthPeriod

    var body: some View {
        // 窗口窄（两边栏都开着）时日期换到第二行，不把内容区撑宽、挤扁左栏
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.l) {
                controls
                title
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                controls
                title
            }
        }
    }

    private var controls: some View {
        let cal = model.calendar
        return HStack(spacing: Theme.Space.l) {
            TabStrip(tabs: HealthPeriod.Scale.allCases.map { ($0.rawValue, $0.label) }, selection: Binding(
                get: { period.scale.rawValue },
                set: { period.scale = HealthPeriod.Scale(rawValue: $0) ?? .day }), large: true)
            HStack(spacing: Theme.Space.s) {
                Button { period = period.stepped(-1, calendar: cal) } label: {
                    Image(systemName: "chevron.left").frame(width: 22)
                }
                .help("往前")
                .accessibilityLabel("往前")
                Button("今天") { period.anchor = model.clock }
                    .disabled(period.contains(model.clock, calendar: cal))
                Button { period = period.stepped(1, calendar: cal) } label: {
                    Image(systemName: "chevron.right").frame(width: 22)
                }
                .help("往后")
                .accessibilityLabel("往后")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .font(.title3)
        }
        .fixedSize()
    }

    private var title: some View {
        Text(Self.title(period, calendar: model.calendar)).font(.title2.weight(.semibold)).monospacedDigit()
            .fixedSize()
    }

    static func title(_ p: HealthPeriod, calendar: Calendar) -> String {
        let days = p.days(calendar: calendar)
        guard let first = days.first, let last = days.last else { return "" }
        switch p.scale {
        case .day: return Fmt.string(first, "yyyy年M月d日 EEE")
        case .week: return Fmt.shortDay(first) + " – " + Fmt.shortDay(last)
        case .month: return Fmt.string(first, "yyyy年M月")
        }
    }
}

/// 一排数字卡片：放得下就一行，窄了自动折成两行（不把内容区撑宽）
struct StatRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.Space.m)], alignment: .leading,
                  spacing: Theme.Space.m) {
            content
        }
    }
}

/// 一个格子要显示的东西：0…1 的深浅（nil = 没有数据，灰）和一行小字
struct HeatCell {
    var fraction: Double?
    var text: String?
}

/// 月历热力格：一格一天，颜色越深数越大；点一天跳到“日”
struct MonthHeatGrid: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let color: Color
    let cell: (Date) -> HeatCell
    let onSelect: (Date) -> Void

    var body: some View {
        let cal = model.calendar
        let lead = days.first.map { (cal.component(.weekday, from: $0) - cal.firstWeekday + 7) % 7 } ?? 0
        let names = (0..<7).map { i in cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1 + i) % 7] }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, n in
                Text(n).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(0..<lead, id: \.self) { i in Color.clear.frame(height: 44).id("lead\(i)") }
            ForEach(days, id: \.self) { d in
                let c = cell(d)
                let isToday = cal.isDate(d, inSameDayAs: model.clock)
                VStack(spacing: 1) {
                    Text("\(cal.component(.day, from: d))").font(.caption.weight(isToday ? .bold : .regular))
                    Text(c.text ?? " ").font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 6).fill(
                    c.fraction.map { color.opacity(0.15 + 0.6 * min(max($0, 0), 1)) } ?? Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isToday ? Color.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
                .onTapGesture { onSelect(d) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
        }
    }
}

/// 按天的柱子（周 / 月），可选一条按天的目标虚线；浅色柱 = 那天没记全
struct DailyBarChart: View {
    struct Point: Identifiable {
        var id: Date { day }
        var day: Date
        var value: Double
        var goal: Double? = nil
        var faded = false
    }

    /// 目标线的颜色：和三页用到的柱子颜色（橙、绿、蓝、靛）都不撞
    static let goalColor = Theme.red

    let title: String
    let points: [Point]
    let color: Color
    var height: CGFloat = 140
    /// 柱子上 y 轴怎么写（默认整数）
    var axisLabel: (Double) -> String = { "\(Int($0))" }

    var body: some View {
        let monthly = points.count > 7
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("日期", p.day, unit: .day), y: .value(title, p.value))
                        .foregroundStyle(color.opacity(p.faded ? 0.35 : 1).gradient)
                }
                // 目标：红色粗虚线，线尾标“目标 2800”，和柱子一眼分开
                let goals = points.filter { $0.goal != nil }
                ForEach(goals) { p in
                    LineMark(x: .value("日期", p.day, unit: .day), y: .value("目标", p.goal ?? 0), series: .value("线", "目标"))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 4]))
                        .foregroundStyle(Self.goalColor)
                }
                if let last = goals.last, let g = last.goal {
                    PointMark(x: .value("日期", last.day, unit: .day), y: .value("目标", g))
                        .symbolSize(30)
                        .foregroundStyle(Self.goalColor)
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("目标 \(axisLabel(g))").font(.caption2.weight(.semibold)).foregroundStyle(Self.goalColor)
                        }
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    AxisValueLabel { if let n = v.as(Double.self) { Text(axisLabel(n)) } }
                }
            }
            .chartXAxis {
                if monthly {
                    AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.day()) }
                } else {
                    AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
                }
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}
