import SwiftUI
import Charts
import LifeOSCore

/// 营养：选一天看各项和目标比、每顿吃了什么；下面是最近 7 天的热量 / 蛋白质柱状图（只算记全的日子的平均）
struct PhoneNutritionView: View {
    @Environment(PhoneModel.self) private var model
    @State private var day = Date()

    var body: some View {
        let cal = model.calendar
        let diet = model.health.day(day, calendar: cal)
        let target = model.health.targets(on: day, calendar: cal)

        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("前一天")
                        Spacer()
                        Text(Fmt.relativeDay(day, now: model.clock, calendar: cal) + " · " + Fmt.day(day)).font(.headline)
                        Spacer()
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("后一天")
                            .disabled(cal.isDate(day, inSameDayAs: model.clock))
                    }
                    .buttonStyle(.borderless)
                    if diet.complete == false {
                        Label("这天只记了一部分", systemImage: "circle.lefthalf.filled")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    NutrientBars(total: diet.total, target: target)
                }
                Section("吃了什么") {
                    if diet.meals.isEmpty {
                        Text("这天还没有记录").foregroundStyle(.secondary)
                    }
                    ForEach(diet.meals) { meal in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(meal.time).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let n = meal.nutrition {
                                    Text("\(Int(n.kcal)) 千卡 · 蛋白 \(Int(n.protein)) g")
                                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                } else {
                                    Text("待估算").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                            Text(meal.text).font(.callout)
                        }
                    }
                }
                Section("最近 7 天") {
                    WeekNutritionChart(until: day)
                }
            }
            .navigationTitle("营养")
            .toolbar { SettingsButton() }
            .refreshable { model.reload() }
        }
    }

    private func shift(_ n: Int) {
        guard let d = model.calendar.date(byAdding: .day, value: n, to: day) else { return }
        day = min(d, model.clock)
    }
}

/// 热量、蛋白、碳水、脂肪，加上钠和添加糖（这两项是上限）
struct NutrientBars: View {
    let total: Nutrition
    let target: Nutrition?

    var body: some View {
        VStack(spacing: 10) {
            bar("热量", total.kcal, target?.kcal, "千卡", tint: Theme.blue)
            bar("蛋白质", total.protein, target?.protein, "g", tint: Theme.green)
            bar("碳水", total.carbs, target?.carbs, "g", tint: Theme.teal)
            bar("脂肪", total.fat, target?.fat, "g", tint: Theme.indigo)
            ForEach(["sodium", "sugar"], id: \.self) { key in
                if let m = Micronutrient.byKey(key), let goal = target?.micros[key] {
                    bar(m.label, total.micros[key] ?? 0, goal, m.unit, tint: Theme.orange, isLimit: true)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func bar(_ label: String, _ value: Double, _ goal: Double?, _ unit: String, tint: Color, isLimit: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.callout)
                Spacer()
                Text(goal.map { "\(Int(value)) / \(Int($0)) \(unit)" + (isLimit ? " 上限" : "") } ?? "\(Int(value)) \(unit)")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            if let goal, goal > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.15))
                        Capsule().fill(tint).frame(width: g.size.width * min(value / goal, 1))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 7 天热量柱 + 目标线；只记了一部分的日子用浅色柱
struct WeekNutritionChart: View {
    @Environment(PhoneModel.self) private var model
    let until: Date

    var body: some View {
        let cal = model.calendar
        let end = cal.startOfDay(for: until)
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: end) }
        let summary = model.health.nutritionSummary(days, today: model.clock, calendar: cal)
        let target = model.health.targets(on: until, calendar: cal)

        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(days, id: \.self) { d in
                    let diet = model.health.day(d, calendar: cal)
                    let full = diet.isComplete(today: model.clock, calendar: cal)
                    BarMark(x: .value("日期", d, unit: .day), y: .value("热量", diet.total.kcal))
                        .foregroundStyle(full ? Theme.blue : Theme.blue.opacity(0.3))
                }
                if let kcal = target?.kcal {
                    RuleMark(y: .value("目标", kcal))
                        .foregroundStyle(Theme.red)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
            }
            .frame(height: 140)
            if let avg = summary.average {
                Text("记全的 \(summary.completeDays.count) 天平均：\(Int(avg.kcal)) 千卡 · 蛋白 \(Int(avg.protein)) g")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("这 7 天没有记全的日子").font(.footnote).foregroundStyle(.secondary)
            }
            if summary.partialDays > 0 {
                Text("浅色柱是只记了一部分的日子（\(summary.partialDays) 天），不算进平均")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// 今天页上的小结：热量和蛋白质还差多少
struct NutritionMiniCard: View {
    @Environment(PhoneModel.self) private var model
    let day: Date

    var body: some View {
        let cal = model.calendar
        let total = model.health.day(day, calendar: cal).total
        if let t = model.health.targets(on: day, calendar: cal) {
            HStack(spacing: 16) {
                stat("热量", total.kcal, t.kcal, "千卡")
                stat("蛋白质", total.protein, t.protein, "g")
            }
        }
    }

    private func stat(_ label: String, _ v: Double, _ goal: Double, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: "\(Int(v)) / \(Int(goal)) \(unit)").font(.callout).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
