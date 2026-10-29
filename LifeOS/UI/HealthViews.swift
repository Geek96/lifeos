import SwiftUI
import Charts
import LifeOSCore

// 健康插件的界面：今天卡片、营养页和健身与锻炼页、三页共用的外框、圆环、记一顿。
// 只显示事实（吃了多少、目标多少、还差多少），不打分、不评价、不催。

/// 三个同心圆环：外 热量 / 中 蛋白质 / 内 碳水（像 Apple 健身的活动圆环）
struct NutritionRings: View {
    let total: Nutrition
    let target: Nutrition
    var size: CGFloat = 120

    static let kcalColor = Theme.orange
    static let proteinColor = Theme.green
    static let carbsColor = Theme.blue

    var body: some View {
        let line = size * 0.11
        let gap = line * 0.25
        ZStack {
            ring(total.kcal, target.kcal, Self.kcalColor, inset: 0, line: line)
            ring(total.protein, target.protein, Self.proteinColor, inset: line + gap, line: line)
            ring(total.carbs, target.carbs, Self.carbsColor, inset: 2 * (line + gap), line: line)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("热量 \(Int(total.kcal)) / \(Int(target.kcal)) 千卡，蛋白质 \(Int(total.protein)) / \(Int(target.protein)) 克，碳水 \(Int(total.carbs)) / \(Int(target.carbs)) 克")
    }

    private func ring(_ value: Double, _ goal: Double, _ color: Color, inset: CGFloat, line: CGFloat) -> some View {
        let p = goal > 0 ? value / goal : 0
        return ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: min(p, 1))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // 超过目标：再叠一圈深色，看得出“多了”
            if p > 1 {
                Circle().trim(from: 0, to: min(p - 1, 1))
                    .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: line * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .padding(inset + line / 2)
        .animation(.snappy, value: value)
    }
}

/// 圆环右边的数字：已吃 / 目标 · 还差
struct NutritionLegend: View {
    let total: Nutrition
    let target: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("热量", total.kcal, target.kcal, "千卡", NutritionRings.kcalColor)
            row("蛋白质", total.protein, target.protein, "g", NutritionRings.proteinColor)
            row("碳水", total.carbs, target.carbs, "g", NutritionRings.carbsColor)
            row("脂肪", total.fat, target.fat, "g", .secondary)
        }
        .font(.callout)
    }

    private func row(_ name: String, _ value: Double, _ goal: Double, _ unit: String, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name).frame(width: 44, alignment: .leading)
            Text("\(Int(value.rounded())) / \(Int(goal.rounded())) \(unit)").monospacedDigit()
            let left = goal - value
            Text(left > 0 ? "还差 \(Int(left.rounded()))" : "已到")
                .foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// 记一顿：一句话写进今天的饮食表，数字留给 agent 估算
struct MealLogField: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""

    var body: some View {
        HStack {
            TextField("记一顿，比如“午饭 Chick-fil-A 烤鸡块 12 块”", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button("记下", action: save)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func save() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        model.logMeal(t)
        draft = ""
    }
}

/// 有几条还没估算时提示一下
struct PendingMealsHint: View {
    @Environment(AppModel.self) private var model
    let count: Int

    var body: some View {
        if count > 0 {
            HStack {
                Label("\(count) 条还没估算，圆环暂时没算进去", systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

/// 今天视图里的健康卡片：今天练什么 + 圆环 + 记一顿
struct HealthTodayCard: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isToday: Bool

    var body: some View {
        let diet = model.health.day(day, calendar: model.calendar)
        let training = model.training(on: day)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionTitle(text: "健康", systemImage: "heart")
                Spacer()
                Button("详细") { model.page = .nutrition }
                    .buttonStyle(.link)
            }
            HStack(alignment: .top, spacing: Theme.Space.xl) {
                // 翻到以前的日子：按那天当时的目标
                if let target = model.health.targets(on: day, calendar: model.calendar) {
                    NutritionRings(total: diet.total, target: target, size: 104)
                    NutritionLegend(total: diet.total, target: target)
                } else {
                    Text("还没有每日目标（健康/目标.md）。").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if diet.complete == false {
                Label("这天只记了一部分，不算进平均", systemImage: "circle.lefthalf.filled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !training.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(training, id: \.occurrence.id) { t in
                        TrainingSummary(occurrence: t.occurrence, item: t.item, maxRows: 5)
                    }
                }
            }
            if let night = model.health.sleep(on: day, calendar: model.calendar), let minutes = night.minutes {
                Label("昨晚睡了 \(HealthFormat.sleepText(minutes))（\(night.bedtime ?? "?")–\(night.wake ?? "?")）", systemImage: "bed.double")
                    .font(.callout).foregroundStyle(.secondary)
                    .onTapGesture { model.page = .rest }
            }
            if isToday {
                MealLogField()
                PendingMealsHint(count: diet.pendingCount)
            }
        }
        .padding(Theme.Space.l)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// 一次训练：时间 + 标题 + 正文第一张表的前几行
struct TrainingSummary: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let item: LifeItem
    var maxRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Theme.green)
                Text(Fmt.time(occurrence.start)).monospacedDigit().foregroundStyle(.secondary)
                Text(item.title).fontWeight(.medium)
            }
            if let plan = TrainingPlan.firstTable(in: item.body) {
                let rows = TrainingPlan.rows(plan.rows, for: occurrence.start, calendar: model.calendar)
                ForEach(Array(rows.prefix(maxRows).enumerated()), id: \.offset) { _, row in
                    Text(row.filter { !$0.isEmpty }.prefix(3).joined(separator: "  ·  "))
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.leading, 26)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.selected = occurrence; model.showInspector = true }
    }
}

/// 健康三页（营养 / 健身与锻炼 / 休息睡眠与心理健康）共用的外框：大标题 + 可选分页条 + 内容
struct HealthPageScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(title).font(.largeTitle.bold())
                content
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// 营养页：今天（圆环、记一顿、吃了什么、最近 7 天）/ 微量营养（今天每一项、近 7 天平均）
struct NutritionView: View {
    @AppStorage("nutritionTab") private var tab = NutritionTab.today.rawValue

    enum NutritionTab: String, CaseIterable, Identifiable {
        case today, nutrition
        var id: String { rawValue }
        var label: String {
            switch self { case .today: "今天"; case .nutrition: "微量营养" }
        }
    }

    var body: some View {
        HealthPageScaffold(title: "营养") {
            TabStrip(tabs: NutritionTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
            switch NutritionTab(rawValue: tab) ?? .today {
            case .today: NutritionTodayPage()
            case .nutrition: HealthNutritionPage()
            }
        }
    }
}

/// 营养 · 今天：圆环 + 记一顿 + 今天吃了什么 + 最近 7 天
struct NutritionTodayPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let diet = model.health.day(model.clock, calendar: model.calendar)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                if let target = model.health.targets(on: model.clock, calendar: model.calendar) {
                    NutritionRings(total: diet.total, target: target, size: 150)
                    NutritionLegend(total: diet.total, target: target)
                } else {
                    Text("还没有每日目标（健康/目标.md）。").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                MealLogField()
                PendingMealsHint(count: diet.pendingCount)
            }

            if !diet.meals.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "今天吃了什么（\(diet.meals.count) 条）", systemImage: "fork.knife")
                    MealTable(meals: diet.meals)
                }
            }

            WeekNutritionChart()
        }
    }
}

/// 健身与锻炼页：这周数字 + 今天练什么，下面分页：计划与动作（肌肉图、一周计划、身体与复测、动作）/ 训练记录
struct FitnessView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fitnessTab") private var tab = FitnessTab.plan.rawValue

    enum FitnessTab: String, CaseIterable, Identifiable {
        case plan, log
        var id: String { rawValue }
        var label: String {
            switch self { case .plan: "计划与动作"; case .log: "训练记录" }
        }
    }

    var body: some View {
        let current = FitnessTab(rawValue: tab) ?? .plan
        HealthPageScaffold(title: "健身与锻炼") {
            // 打开了某个动作：整页给动作详情
            if current == .plan, model.openExerciseID != nil {
                FitnessPage()
            } else {
                FitnessThisWeek()
                TabStrip(tabs: FitnessTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
                switch current {
                case .plan: FitnessPage()
                case .log: HealthLogPage()
                }
            }
        }
        // 换到别的分页 / 别的页才收起动作详情（打开动作时会把分页写成 plan，那次不算）
        .onChange(of: tab) { if tab != FitnessTab.plan.rawValue { model.openExerciseID = nil } }
        .onChange(of: model.page) { if model.page != .fitness { model.openExerciseID = nil } }
    }
}

/// 健身与锻炼页顶上：这周的数字 + 今天练什么
struct FitnessThisWeek: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let today = model.clock
        let training = model.training(on: today)
        let week = WeekStats.compute(model.health.sessions, calendar: cal)
            .first { cal.isDate($0.weekStart, equalTo: today, toGranularity: .weekOfYear) }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "这周训练", value: "\(week?.sessions ?? 0) 次")
                StatTile(title: "这周跑了", value: week.map { String(format: "%.1f km", $0.runKm) } ?? "0 km")
                StatTile(title: "平均配速", value: week?.pace.map { HealthFormat.minutesText($0) + " /km" } ?? "—")
            }
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "今天练什么", systemImage: "figure.strengthtraining.traditional")
                if training.isEmpty {
                    Text("今天休息。").foregroundStyle(.secondary)
                } else {
                    ForEach(training, id: \.occurrence.id) { t in
                        TrainingSummary(occurrence: t.occurrence, item: t.item, maxRows: 8)
                    }
                }
            }
        }
    }
}

/// 一个小数字卡片
struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.m)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

/// 测试：所有复测的对比表 + 每项指标的变化曲线
struct HealthTestsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tests = model.health.tests
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if tests.isEmpty {
                Text("还没有复测记录。").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) { TestsTable(tests: tests, limit: nil) }
                let numeric = HealthTest.labels.compactMap { l -> (String, [(Date, Double)])? in
                    let pts = tests.compactMap { t -> (Date, Double)? in
                        guard let v = t.fields.first(where: { $0.key == l.key })?.value else { return nil }
                        let n = l.key == "mile" ? HealthStore.minutes(v) : HealthStore.number(v)
                        return n.map { (t.date, $0) }
                    }
                    return pts.count >= 2 ? (l.label, pts) : nil
                }
                if numeric.isEmpty {
                    Text("同一项指标测到两次以上，这里会画出变化曲线。").font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Space.l) {
                        ForEach(numeric, id: \.0) { label, pts in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(label).font(.caption).foregroundStyle(.secondary)
                                Chart(pts, id: \.0) { p in
                                    LineMark(x: .value("日期", p.0), y: .value(label, p.1))
                                    PointMark(x: .value("日期", p.0), y: .value(label, p.1))
                                }
                                .chartYScale(domain: .automatic(includesZero: false))
                                .frame(height: 120)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 训练记录：每周统计 + 归档
struct HealthLogPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sessions = model.health.sessions
        let weeks = Array(WeekStats.compute(sessions, calendar: model.calendar).suffix(12))
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if sessions.isEmpty {
                Text("还没有训练记录。练完跟 agent 说一句（比如“跑了 2.1 km，13 分 20 秒”“卧推 70 lb 3×8”），它会记到 健康/训练记录/。")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "每周变化", systemImage: "chart.bar")
                    HStack(spacing: Theme.Space.l) {
                        weekBars(weeks.map { ($0.weekStart, $0.runKm) }, title: "总里程（km）", color: Theme.blue)
                        weekBars(weeks.map { ($0.weekStart, $0.volume) }, title: "力量训练量（lb×次）", color: Theme.green)
                    }
                    let paced = weeks.compactMap { w in w.pace.map { (w.weekStart, $0) } }
                    if !paced.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("平均配速（分钟 / km，越低越快）").font(.caption).foregroundStyle(.secondary)
                            Chart(paced, id: \.0) { p in
                                LineMark(x: .value("周", p.0, unit: .weekOfYear), y: .value("配速", p.1))
                                PointMark(x: .value("周", p.0, unit: .weekOfYear), y: .value("配速", p.1))
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartYAxis {
                                AxisMarks { v in
                                    AxisGridLine()
                                    AxisValueLabel { if let m = v.as(Double.self) { Text(HealthFormat.minutesText(m)) } }
                                }
                            }
                            .frame(height: 130)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "归档", systemImage: "archivebox")
                    ForEach(sessions) { s in SessionRow(session: s) }
                }
            }
        }
    }

    private func weekBars(_ data: [(Date, Double)], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart(data, id: \.0) { d in
                BarMark(x: .value("周", d.0, unit: .weekOfYear), y: .value(title, d.1))
                    .foregroundStyle(color.gradient)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { _ in AxisValueLabel(format: .dateTime.month(.defaultDigits).day()) }
            }
            .frame(height: 140)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 归档里的一次训练：一行摘要，点开看每组 / 备注
struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: HealthSession
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 4) {
                if let t = session.table {
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { _, row in
                        Text(row.filter { !$0.isEmpty }.joined(separator: "  ·  ")).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !session.note.isEmpty { Text(session.note).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(.leading, 28)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: session.kind == .run ? "figure.run" : "dumbbell")
                    .foregroundStyle(session.kind == .run ? Theme.blue : Theme.green).frame(width: 18)
                Text(Fmt.string(session.date, "M月d日 EEE")).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 92, alignment: .leading)
                Text(session.title).fontWeight(.medium)
                Spacer()
                Text(summary).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if let d = session.distanceKm { parts.append(String(format: "%.1f km", d)) }
        if let m = session.minutes { parts.append(HealthFormat.minutesText(m)) }
        if let p = session.pace { parts.append(HealthFormat.minutesText(p) + " /km") }
        if let v = session.volume { parts.append("\(Int(v)) lb×次") }
        return parts.joined(separator: " · ")
    }
}

struct MealTable: View {
    let meals: [Meal]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("时间"); Text("吃了什么"); Text("热量"); Text("蛋白质"); Text("碳水"); Text("脂肪")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(meals) { m in
                GridRow {
                    Text(m.time).monospacedDigit().foregroundStyle(.secondary)
                    Text(m.text).lineLimit(2)
                    if let n = m.nutrition {
                        Text("\(Int(n.kcal))").monospacedDigit()
                        Text("\(Int(n.protein)) g").monospacedDigit()
                        Text("\(Int(n.carbs)) g").monospacedDigit()
                        Text("\(Int(n.fat)) g").monospacedDigit()
                    } else {
                        Text("待估算").foregroundStyle(.secondary).gridCellColumns(4)
                    }
                }
            }
        }
        .font(.callout)
    }
}

/// 最近 7 天的热量和蛋白质，虚线是目标
struct WeekNutritionChart: View {
    @Environment(AppModel.self) private var model

    private struct Point: Identifiable {
        var id: Date { day }
        var day: Date
        var value: Double
        /// 那天当时的目标
        var goal: Double?
        /// 记全了才是实心；只记了一半 / 今天还在吃是浅色
        var complete: Bool
    }

    /// 最近 7 天每天的某一项（热量、蛋白质 …）：吃了多少、那天的目标、记全了没有
    private func points(_ value: (Nutrition) -> Double) -> [Point] {
        let cal = model.calendar
        let end = cal.startOfDay(for: model.clock)
        return (0..<7).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: end) else { return nil }
            let diet = model.health.day(d, calendar: cal)
            return Point(day: d, value: value(diet.total), goal: model.health.targets(on: d, calendar: cal).map(value),
                         complete: diet.isComplete(today: model.clock, calendar: cal))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(text: "最近 7 天", systemImage: "chart.bar")
            HStack(spacing: Theme.Space.l) {
                chart(points(\.kcal), title: "热量（千卡）", color: NutritionRings.kcalColor)
                chart(points(\.protein), title: "蛋白质（g）", color: NutritionRings.proteinColor)
            }
            Text("浅色 = 只记了一部分或今天还没吃完；虚线 = 那天当时的目标。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chart(_ data: [Point], title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Chart {
                ForEach(data) { p in
                    BarMark(x: .value("日期", p.day, unit: .day), y: .value(title, p.value))
                        .foregroundStyle(color.opacity(p.complete ? 1 : 0.35).gradient)
                }
                // 目标改过的话，虚线在那天跳一下
                ForEach(data.filter { $0.goal != nil }) { p in
                    LineMark(x: .value("日期", p.day, unit: .day), y: .value("目标", p.goal ?? 0), series: .value("线", "目标"))
                        .interpolationMethod(.stepCenter)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 140)
        }
        .frame(maxWidth: .infinity)
    }
}

/// 复测：每次一列，指标一行
struct TestsTable: View {
    let tests: [HealthTest]
    var limit: Int? = 4

    var body: some View {
        let shown = limit.map { Array(tests.suffix($0)) } ?? tests
        let keys = HealthTest.labels.filter { l in shown.contains { t in t.fields.contains { $0.key == l.key } } }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "复测", systemImage: "ruler")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    ForEach(shown) { t in Text(Fmt.shortDay(t.date)).font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(keys, id: \.key) { k in
                    GridRow {
                        Text(k.label).foregroundStyle(.secondary)
                        ForEach(shown) { t in
                            Text(t.fields.first { $0.key == k.key }?.value ?? "—").monospacedDigit()
                        }
                    }
                }
            }
            .font(.callout)
        }
    }
}


// MARK: - 微量营养

/// 一项营养的进度条：目标型吃到 100% 变绿；上限型超过就变橙
struct MicroBar: View {
    let nutrient: Micronutrient
    let value: Double
    let target: Double

    var body: some View {
        let p = target > 0 ? value / target : 0
        let over = nutrient.isLimit && p > 1
        let color: Color = nutrient.isLimit ? (over ? Theme.orange : Theme.teal) : (p >= 1 ? Theme.green : Theme.blue)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(nutrient.label).font(.callout.weight(.medium))
                if nutrient.isLimit { Text("上限").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Text("\(Self.fmt(value)) / \(Self.fmt(target)) \(nutrient.unit)").font(.caption).monospacedDigit()
                    .foregroundStyle(over ? Theme.orange : .secondary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: g.size.width * min(p, 1))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nutrient.label) \(Self.fmt(value)) / \(Self.fmt(target)) \(nutrient.unit)")
    }

    static func fmt(_ v: Double) -> String {
        v >= 100 || v == v.rounded() ? "\(Int(v.rounded()))" : String(format: "%.1f", v)
    }
}

/// 目标文件里写了的那些营养素
struct MicroGrid: View {
    let total: Nutrition
    let target: Nutrition
    var compact = false

    var body: some View {
        let items = Micronutrient.all.filter { target.micros[$0.key] != nil }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 150 : 200), spacing: Theme.Space.l)], spacing: Theme.Space.m) {
            ForEach(items) { m in
                MicroBar(nutrient: m, value: total.micros[m.key] ?? 0, target: target.micros[m.key] ?? 0)
            }
        }
    }
}

/// 营养：今天每一项 + 近 7 天平均 + 一直偏低 / 偏高的
struct HealthNutritionPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let today = model.health.day(model.clock, calendar: cal)
        // 只算记全了的日子；今天还在吃、只记了一半的都不算，免得把平均拉低
        let recent = model.health.completeDays(last: 7, until: model.clock, today: model.clock, calendar: cal)
        let partial = (1..<7).filter { back in
            guard let d = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: model.clock)) else { return false }
            return model.health.day(d, calendar: cal).complete == false
        }.count
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let target = model.health.targets(on: model.clock, calendar: cal), !target.micros.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "今天", systemImage: "sun.max")
                    MicroGrid(total: today.total, target: target)
                }

                if recent.isEmpty {
                    Text("记全几天以后，这里会显示近 7 天的平均。").foregroundStyle(.secondary)
                } else {
                    let avg = average(recent.map(\.total))
                    // 这几天的目标可能不一样（中间改过），平均也按当时的目标平均
                    let target = average(recent.compactMap { model.health.targets(on: $0.date, calendar: cal) })
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionTitle(text: "近 7 天平均（记全的 \(recent.count) 天）", systemImage: "calendar")
                        if partial > 0 {
                            Text("另有 \(partial) 天只记了一部分，没算进去。").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack(spacing: Theme.Space.m) {
                            StatTile(title: "热量", value: "\(Int(avg.kcal)) / \(Int(target.kcal))")
                            StatTile(title: "蛋白质", value: "\(Int(avg.protein)) / \(Int(target.protein)) g")
                        }
                        MicroGrid(total: avg, target: target)
                    }
                    let (low, high) = flags(avg, target)
                    if !low.isEmpty || !high.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: "这一周的规律", systemImage: "lightbulb")
                            if !high.isEmpty { Label("超过上限：" + high.joined(separator: "、"), systemImage: "arrow.up.circle").foregroundStyle(Theme.orange) }
                            if !low.isEmpty { Label("平均不到推荐量的七成：" + low.joined(separator: "、"), systemImage: "arrow.down.circle").foregroundStyle(Theme.blue) }
                            Text("微量营养是按描述估的，单天不一定准，看一周的规律更可靠。").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("健康/目标.md 里还没写微量营养的目标（sodium、fiber、vitamin_d …）。").foregroundStyle(.secondary)
            }
        }
    }

    private func average(_ values: [Nutrition]) -> Nutrition {
        guard !values.isEmpty else { return .zero }
        let sum = values.reduce(.zero, +)
        let n = Double(values.count)
        return Nutrition(kcal: sum.kcal / n, protein: sum.protein / n, carbs: sum.carbs / n, fat: sum.fat / n,
                         micros: sum.micros.mapValues { $0 / n })
    }

    private func flags(_ avg: Nutrition, _ target: Nutrition) -> (low: [String], high: [String]) {
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
