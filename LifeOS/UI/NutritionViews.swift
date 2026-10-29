import SwiftUI
import Charts
import LifeOSCore

// 营养页：日（圆环、记一顿 / 补记、吃了什么、微量营养）/ 周、月（记了几天、平均对照当时的目标、按天的图、月历热力格），
// 下面是体重（记体重、趋势、对照增肌目标的范围）。
// 只陈述数字，不打分、不评价。

struct NutritionView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("nutritionScale") private var scale = HealthPeriod.Scale.day.rawValue
    @State private var anchor = Date()

    var body: some View {
        let period = HealthPeriod(scale: HealthPeriod.Scale(rawValue: scale) ?? .day, anchor: anchor)
        HealthPageScaffold(title: "营养") {
            HealthPeriodBar(period: Binding(get: { period }, set: { scale = $0.scale.rawValue; anchor = $0.anchor }))
            switch period.scale {
            case .day: NutritionDayPage(day: anchor)
            case .week, .month:
                NutritionRangePage(period: period) { d in anchor = d; scale = HealthPeriod.Scale.day.rawValue }
            }
            Divider()
            // 在“日”里记到正在看的那天，周 / 月里默认今天
            WeightSection(day: period.scale == .day ? anchor : model.clock)
        }
    }
}

/// 营养 · 日
struct NutritionDayPage: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let cal = model.calendar
        let diet = model.health.day(day, calendar: cal)
        let target = model.health.targets(on: day, calendar: cal)
        let future = cal.startOfDay(for: day) > cal.startOfDay(for: model.clock)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                if let target {
                    NutritionRings(total: diet.total, target: target, size: 150)
                    NutritionLegend(total: diet.total, target: target)
                } else {
                    Text("还没有每日目标（健康/目标.md）。").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Label(status(diet), systemImage: diet.complete == false ? "circle.lefthalf.filled" : "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary)

            if !future {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    MealLogField(day: day)
                    PendingMealsHint(count: diet.pendingCount)
                }
            }

            if !diet.meals.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "吃了什么（\(diet.meals.count) 条）", systemImage: "fork.knife")
                    MealTable(meals: diet.meals)
                }
            }

            if let target, !target.micros.isEmpty, diet.meals.contains(where: \.isEstimated) {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "微量营养", systemImage: "leaf")
                    MicroGrid(total: diet.total, target: target)
                    Text("微量营养是按描述估的，单天不一定准，看周、月的平均更可靠。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func status(_ diet: DietDay) -> String {
        if diet.meals.isEmpty { return "这天没有记录" }
        if diet.complete == false { return "这天只记了一部分，不算进平均" }
        if diet.isComplete(today: model.clock, calendar: model.calendar) { return "记全了，算进平均" }
        return "今天还在记；记完跟 agent 说一声“今天都记了”，就算进平均"
    }
}

/// 营养 · 周 / 月
struct NutritionRangePage: View {
    @Environment(AppModel.self) private var model
    let period: HealthPeriod
    let onSelectDay: (Date) -> Void

    var body: some View {
        let cal = model.calendar
        let days = period.days(calendar: cal)
        let summary = model.health.nutritionSummary(days, today: model.clock, calendar: cal)
        let monthly = period.scale == .month
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            StatRow {
                StatTile(title: "记了", value: "\(summary.loggedDays) / \(days.count) 天")
                StatTile(title: "记全的", value: "\(summary.completeDays.count) 天")
                StatTile(title: "平均热量", value: pair(summary.average?.kcal, summary.averageTarget?.kcal, ""))
                StatTile(title: "平均蛋白质", value: pair(summary.average?.protein, summary.averageTarget?.protein, " g"))
            }
            if summary.partialDays > 0 {
                Text("另有 \(summary.partialDays) 天只记了一部分，平均没算它们。").font(.caption).foregroundStyle(.secondary)
            }

            if monthly {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "每天吃到目标热量的几成", systemImage: "square.grid.3x3")
                    MonthHeatGrid(days: days, color: NutritionRings.kcalColor, cell: heat, onSelect: onSelectDay)
                    Text("颜色越深越接近目标；灰 = 没记或还没估算。点一天看那天。").font(.caption).foregroundStyle(.secondary)
                }
            }

            let layout = monthly ? AnyLayout(VStackLayout(spacing: Theme.Space.l)) : AnyLayout(HStackLayout(spacing: Theme.Space.l))
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "每天", systemImage: "chart.bar")
                layout {
                    DailyBarChart(title: "热量（千卡）", points: points(days, \.kcal), color: NutritionRings.kcalColor)
                    DailyBarChart(title: "蛋白质（g）", points: points(days, \.protein), color: NutritionRings.proteinColor)
                    if monthly {
                        DailyBarChart(title: "碳水（g）", points: points(days, \.carbs), color: NutritionRings.carbsColor)
                    }
                }
                Text("浅色 = 只记了一部分或那天还没吃完；红色虚线 = 那天当时的目标。").font(.caption).foregroundStyle(.secondary)
            }

            if let avg = summary.average, let target = summary.averageTarget, !target.micros.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "微量营养平均（记全的 \(summary.completeDays.count) 天）", systemImage: "leaf")
                    MicroGrid(total: avg, target: target)
                    let (low, high) = Self.flags(avg, target)
                    if !high.isEmpty { Label("平均超过上限：" + high.joined(separator: "、"), systemImage: "arrow.up.circle").foregroundStyle(Theme.orange) }
                    if !low.isEmpty { Label("平均不到推荐量的七成：" + low.joined(separator: "、"), systemImage: "arrow.down.circle").foregroundStyle(Theme.blue) }
                }
            } else if summary.completeDays.isEmpty {
                Text("这段时间还没有记全的日子，记全以后这里会显示平均。").foregroundStyle(.secondary)
            }
        }
    }

    private func pair(_ value: Double?, _ goal: Double?, _ unit: String) -> String {
        guard let value else { return "—" }
        return goal.map { "\(Int(value)) / \(Int($0))\(unit)" } ?? "\(Int(value))\(unit)"
    }

    private func points(_ days: [Date], _ value: (Nutrition) -> Double) -> [DailyBarChart.Point] {
        let cal = model.calendar
        return days.map { d in
            let diet = model.health.day(d, calendar: cal)
            return .init(day: d, value: value(diet.total), goal: model.health.targets(on: d, calendar: cal).map(value),
                         faded: !diet.isComplete(today: model.clock, calendar: cal))
        }
    }

    private func heat(_ d: Date) -> HeatCell {
        let cal = model.calendar
        let diet = model.health.day(d, calendar: cal)
        guard diet.meals.contains(where: \.isEstimated) else { return HeatCell() }
        let kcal = diet.total.kcal
        let goal = model.health.targets(on: d, calendar: cal)?.kcal ?? 0
        return HeatCell(fraction: goal > 0 ? kcal / goal : nil, text: "\(Int(kcal))")
    }

    static func flags(_ avg: Nutrition, _ target: Nutrition) -> (low: [String], high: [String]) {
        var low: [String] = [], high: [String] = []
        for m in Micronutrient.all {
            guard let t = target.micros[m.key], t > 0 else { continue }
            let v = avg.micros[m.key] ?? 0
            if m.isLimit, v > t { high.append(m.label) }
            if !m.isLimit, v < 0.7 * t { low.append(m.label) }
        }
        return (low, high)
    }
}

/// 体重：记一次 + 现在多少、比起点变了多少 + 趋势图（绿色带 = 按目标每月增减的范围）
struct WeightSection: View {
    @Environment(AppModel.self) private var model
    let day: Date
    @State private var draft = ""

    private struct BandPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var low: Double
        var high: Double
    }

    var body: some View {
        let h = model.health
        let latest = h.weights.last
        let base = h.weightBaseline
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionTitle(text: "体重", systemImage: "scalemass")
            HStack {
                TextField("记体重，比如 145 或 65.8 kg（\(Fmt.shortDay(day))）", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("记下", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            StatRow {
                StatTile(title: "最近一次", value: latest.map { Self.text($0.lb) } ?? "—")
                StatTile(title: "比起点", value: delta(latest, base))
                StatTile(title: "最近 4 周", value: h.weightChange(days: 28, until: model.clock, calendar: model.calendar)
                    .map(Self.signed) ?? "—")
                StatTile(title: "目标每月", value: h.weightPlan.map { Self.rate($0) } ?? "—")
            }
            if h.weights.isEmpty {
                Text("还没有体重记录。每周挑一天早上空腹称一次，记在上面或者跟 agent 说。").foregroundStyle(.secondary)
            } else {
                chart
                Text("蓝线是每次称的；绿色带是从起点（\(base.map { Fmt.shortDay($0.date) } ?? "—")）按目标每月增减算出来的范围。一周内上下 1–2 lb 是正常波动，看几周的走向。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        let h = model.health
        let band: [BandPoint] = {
            guard let plan = h.weightPlan, let base = h.weightBaseline else { return [] }
            let end = max(h.weights.last?.date ?? base.date, model.clock).addingTimeInterval(30 * 86400)
            return stride(from: base.date.timeIntervalSince1970, through: end.timeIntervalSince1970, by: 7 * 86400).map { t in
                let d = Date(timeIntervalSince1970: t)
                let b = plan.band(from: base, at: d)
                return BandPoint(date: d, low: b.low, high: b.high)
            }
        }()
        return Chart {
            ForEach(band) { b in
                AreaMark(x: .value("日期", b.date), yStart: .value("下限", b.low), yEnd: .value("上限", b.high), series: .value("线", "目标"))
                    .foregroundStyle(Theme.green.opacity(0.18))
            }
            ForEach(h.weights) { w in
                LineMark(x: .value("日期", w.date), y: .value("体重", w.lb), series: .value("线", "体重"))
                    .foregroundStyle(Theme.blue)
                PointMark(x: .value("日期", w.date), y: .value("体重", w.lb))
                    .foregroundStyle(Theme.blue)
                    .annotation(position: .top, spacing: 2) {
                        Text(String(format: "%.1f", w.lb)).font(.caption2).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel { if let lb = v.as(Double.self) { Text("\(Int(lb)) lb") } }
            }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) } }
        .frame(height: 180)
    }

    private func save() {
        if model.recordWeight(day: day, value: draft) { draft = "" }
    }

    private func delta(_ latest: WeightEntry?, _ base: WeightEntry?) -> String {
        guard let latest, let base, latest.date > base.date else { return "—" }
        return Self.signed(latest.lb - base.lb)
    }

    /// 145.2 → “145.2 lb（65.9 kg）”
    static func text(_ lb: Double) -> String {
        String(format: "%.1f lb（%.1f kg）", lb, lb * WeightEntry.kgPerLb)
    }

    /// +1.3 → “+1.3 lb（+0.6 kg）”
    static func signed(_ lb: Double) -> String {
        String(format: "%+.1f lb（%+.1f kg）", lb, lb * WeightEntry.kgPerLb)
    }

    static func rate(_ p: WeightPlan) -> String {
        func f(_ v: Double) -> String { v == v.rounded() ? String(format: "%+.0f", v) : String(format: "%+.1f", v) }
        return "\(f(p.minKgPerMonth))–\(f(p.maxKgPerMonth).replacingOccurrences(of: "+", with: "")) kg"
    }
}
