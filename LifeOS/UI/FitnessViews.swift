import SwiftUI
import Charts
import LifeOSCore

// 健身与锻炼页的“计划与动作”分页：肌肉分布图 → 学期一周计划 → 身体数据与复测 → 动作（点进去看每周最好成绩和下一次怎么练）。

struct FitnessPage: View {
    @Environment(AppModel.self) private var model
    @State private var selectedMuscle: String?

    var body: some View {
        if let id = model.openExerciseID, let ex = model.health.exercises.first(where: { $0.id == id }) {
            ExerciseDetailView(exercise: ex)
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                MuscleMapSection(selected: $selectedMuscle)
                WeekPlanSection()
                BodyAndTestsSection()
                ExerciseListSection()
            }
        }
    }
}

// MARK: - 肌肉分布图

enum MuscleStyle {
    /// 每块肌肉一个颜色（按 Muscle.all 的顺序在色环上均匀取）
    static func color(_ key: String) -> Color {
        let i = Muscle.all.firstIndex { $0.key == key } ?? 0
        let hue = Double(i) / Double(Muscle.all.count)
        return Color(hue: hue, saturation: 0.55, brightness: 0.88)
    }

    /// 文字用的颜色：同色相、更深，浅色（黄、浅绿）的字在白底上也看得清
    static func text(_ key: String) -> Color {
        let i = Muscle.all.firstIndex { $0.key == key } ?? 0
        return Color(hue: Double(i) / Double(Muscle.all.count), saturation: 0.8, brightness: 0.62)
    }

    static func dayShort(_ day: String) -> String {
        day.components(separatedBy: CharacterSet(charactersIn: "、,，")).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: "、")
    }
}

struct MuscleMapSection: View {
    @Environment(AppModel.self) private var model
    @Binding var selected: String?

    var body: some View {
        let coverage = MuscleCoverage.compute(model.health.exercises)
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionTitle(text: "肌肉分布", systemImage: "figure.arms.open")
                Spacer()
                if selected != nil {
                    Button("显示全部") { selected = nil }.buttonStyle(.link)
                }
            }
            if model.health.exercises.isEmpty {
                Text("还没有动作（健康/动作/）。").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: Theme.Space.s) {
                MuscleFigure(title: "正面", regions: BodyMapData.anterior, coverage: coverage, selected: $selected)
                MuscleFigure(title: "背面", regions: BodyMapData.posterior, coverage: coverage, selected: $selected)
            }
            HStack(spacing: Theme.Space.l) {
                legend(opacity: 1, "主要练到")
                legend(opacity: 0.4, "辅助参与")
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2)).frame(width: 14, height: 10)
                    Text("还没练到")
                }
                Spacer()
                Text("点图上的肌肉只看那一块").foregroundStyle(.tertiary)
            }
            .font(.caption).foregroundStyle(.secondary)
            MuscleList(coverage: coverage, selected: $selected)
            Text("肌肉图形来自 react-body-highlighter（MIT License）。每个动作练哪块肌肉写在动作文件里，来源见各动作页。")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func legend(opacity: Double, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.blue.opacity(opacity)).frame(width: 14, height: 10)
            Text(text)
        }
    }
}

/// 一面人体：中间是肌肉多边形，两边是中英文标注和引线
struct MuscleFigure: View {
    let title: String
    let regions: [BodyMapRegion]
    let coverage: [String: MuscleCoverage.Entry]
    @Binding var selected: String?

    private let figureHeight: CGFloat = 380
    private var scale: CGFloat { figureHeight / BodyMapData.size.height }
    private var figureWidth: CGFloat { BodyMapData.size.width * scale }

    private struct Label: Identifiable {
        var id: String { key }
        var key: String
        var anchor: CGPoint
        var y: CGFloat
        var left: Bool
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { geo in
                let x0 = (geo.size.width - figureWidth) / 2
                let labels = layoutLabels(x0: x0, width: geo.size.width)
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for region in regions {
                            for poly in region.polygons {
                                let path = Self.path(poly, scale: scale, dx: x0)
                                ctx.fill(path, with: .color(fill(region.muscle)))
                                if region.muscle == selected {
                                    ctx.stroke(path, with: .color(.primary.opacity(0.8)), lineWidth: 1.5)
                                }
                            }
                        }
                        // 引线
                        for l in labels {
                            var line = Path()
                            let startX = l.left ? colWidth(geo.size.width, x0) - 2 : geo.size.width - colWidth(geo.size.width, x0) + 2
                            line.move(to: CGPoint(x: startX, y: l.y + 8))
                            line.addLine(to: l.anchor)
                            ctx.stroke(line, with: .color(MuscleStyle.color(l.key).opacity(dim(l.key) ? 0.25 : 0.8)), lineWidth: 0.8)
                            ctx.fill(Path(ellipseIn: CGRect(x: l.anchor.x - 2, y: l.anchor.y - 2, width: 4, height: 4)),
                                     with: .color(MuscleStyle.color(l.key)))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { loc in
                        let p = CGPoint(x: (loc.x - x0) / scale, y: loc.y / scale)
                        let hit = regions.first { r in Muscle.named(r.muscle) != nil && r.polygons.contains { Self.contains($0, p) } }
                        selected = hit.map(\.muscle) == selected ? nil : hit?.muscle
                    }
                    ForEach(labels) { l in
                        let m = Muscle.named(l.key)!
                        let w = colWidth(geo.size.width, x0) - 6
                        Button { selected = selected == l.key ? nil : l.key } label: {
                            VStack(alignment: l.left ? .trailing : .leading, spacing: 0) {
                                Text(m.zh).font(.caption2.weight(.semibold)).lineLimit(1)
                                Text(m.en).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .foregroundStyle(coverage[l.key]?.trained == true ? MuscleStyle.text(l.key) : Color.secondary)
                            .frame(width: w, alignment: l.left ? .trailing : .leading)
                            .opacity(dim(l.key) ? 0.35 : 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: l.left ? 0 : geo.size.width - w, y: l.y)
                    }
                }
            }
            .frame(height: figureHeight)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title)肌肉分布图")
    }

    private func colWidth(_ total: CGFloat, _ x0: CGFloat) -> CGFloat { max(60, x0 - 4) }

    private func dim(_ key: String) -> Bool { selected != nil && selected != key }

    private func fill(_ key: String) -> Color {
        guard Muscle.named(key) != nil, let entry = coverage[key] else { return Color.secondary.opacity(0.12) }
        let base: Color = entry.trained ? MuscleStyle.color(key) : Color.secondary
        var opacity = entry.primary.isEmpty ? (entry.trained ? 0.4 : 0.2) : 0.95
        if dim(key) { opacity *= 0.3 }
        return base.opacity(opacity)
    }

    /// 每块肌肉一个标注：按高度从上到下，左右两列交替放；同一列里互相推开不重叠
    private func layoutLabels(x0: CGFloat, width: CGFloat) -> [Label] {
        var byKey: [String: [[Double]]] = [:]
        for r in regions where Muscle.named(r.muscle) != nil { byKey[r.muscle, default: []] += r.polygons }
        let items = byKey.map { key, polys -> (String, [CGPoint]) in
            (key, polys.map { Self.centroid($0) }.map { CGPoint(x: $0.x * scale + x0, y: $0.y * scale) })
        }.sorted { ($0.1.map(\.y).min() ?? 0) < ($1.1.map(\.y).min() ?? 0) }
        var out: [Label] = []
        var lastY: [Bool: CGFloat] = [true: -100, false: -100]
        for (i, item) in items.enumerated() {
            let left = i % 2 == 0
            guard let anchor = left ? item.1.min(by: { $0.x < $1.x }) : item.1.max(by: { $0.x < $1.x }) else { continue }
            let y = min(max(anchor.y - 10, lastY[left]! + 26), figureHeight - 24)
            lastY[left] = y
            out.append(Label(key: item.0, anchor: anchor, y: y, left: left))
        }
        return out
    }

    static func path(_ pts: [Double], scale: CGFloat, dx: CGFloat) -> Path {
        var p = Path()
        guard pts.count >= 6 else { return p }
        p.move(to: CGPoint(x: pts[0] * scale + dx, y: pts[1] * scale))
        var i = 2
        while i + 1 < pts.count {
            p.addLine(to: CGPoint(x: pts[i] * scale + dx, y: pts[i + 1] * scale))
            i += 2
        }
        p.closeSubpath()
        return p
    }

    static func centroid(_ pts: [Double]) -> CGPoint {
        let n = pts.count / 2
        guard n > 0 else { return .zero }
        var x = 0.0, y = 0.0
        for i in 0..<n { x += pts[2 * i]; y += pts[2 * i + 1] }
        return CGPoint(x: x / Double(n), y: y / Double(n))
    }

    /// 射线法判断点在不在多边形里
    static func contains(_ pts: [Double], _ p: CGPoint) -> Bool {
        let n = pts.count / 2
        var inside = false
        var j = n - 1
        for i in 0..<n {
            let xi = pts[2 * i], yi = pts[2 * i + 1], xj = pts[2 * j], yj = pts[2 * j + 1]
            if (yi > p.y) != (yj > p.y), p.x < (xj - xi) * (p.y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }
}

/// 图下面的清单：每块肌肉用什么动作练
struct MuscleList: View {
    @Environment(AppModel.self) private var model
    let coverage: [String: MuscleCoverage.Entry]
    @Binding var selected: String?

    var body: some View {
        let muscles = Muscle.all.filter { selected == nil || $0.key == selected }
        let trained = muscles.filter { coverage[$0.key]?.trained == true }
        let untrained = muscles.filter { coverage[$0.key]?.trained != true }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(trained) { m in
                let e = coverage[m.key]!
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    RoundedRectangle(cornerRadius: 3).fill(MuscleStyle.color(m.key)).frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(m.zh).fontWeight(.medium)
                        Text(m.en).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 150, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if !e.primary.isEmpty { exerciseLine("主要", e.primary, bold: true) }
                        if !e.secondary.isEmpty { exerciseLine("辅助", e.secondary, bold: false) }
                    }
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(selected == m.key ? MuscleStyle.color(m.key).opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            }
            if !untrained.isEmpty {
                Text("还没专门练到：" + untrained.map(\.zh).joined(separator: "、"))
                    .font(.callout).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
    }

    private func exerciseLine(_ label: String, _ list: [Exercise], bold: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            FlowText(items: list.map { ($0.id, $0.name + ($0.day.isEmpty ? "" : "（\(MuscleStyle.dayShort($0.day))）")) }, bold: bold) { id in
                if let ex = list.first(where: { $0.id == id }) { model.openExercise(ex) }
            }
        }
    }
}

/// 一行可点的动作名，用顿号隔开，太长自动换行
struct FlowText: View {
    let items: [(id: String, text: String)]
    var bold = false
    let tap: (String) -> Void

    var body: some View {
        // 用 Text 拼接没法单独点，所以每个是一个按钮；放进自动换行的布局里
        WrapLayout(spacing: 2, lineSpacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button { tap(item.id) } label: {
                    Text(item.text + (i < items.count - 1 ? "、" : ""))
                        .fontWeight(bold ? .medium : .regular)
                        .foregroundStyle(bold ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("打开「\(item.text)」")
            }
        }
    }
}

/// 简单的自动换行布局
struct WrapLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW { y += lineH + lineSpacing; x = 0; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { y += lineH + lineSpacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - 学期一周

struct WeekPlanSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let plan = model.health.plan
        let todayIndex = (model.calendar.component(.weekday, from: model.clock) + 5) % 7 + 1  // 周一 = 1
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "学期中的一周（没有别的事时）", systemImage: "calendar.day.timeline.left")
            if plan.days.isEmpty {
                Text("还没有一周计划（健康/训练计划.md 的“学期一周”表）。").foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow {
                        Text("星期"); Text("时间"); Text("内容"); Text("动作")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                    ForEach(plan.days) { d in
                        let today = WeekPlan.index(of: d.weekday) == todayIndex
                        GridRow(alignment: .firstTextBaseline) {
                            Text(d.weekday).fontWeight(today ? .bold : .medium)
                            Text(d.time.isEmpty ? "—" : d.time).monospacedDigit().foregroundStyle(.secondary)
                            Text(d.what).fontWeight(today ? .semibold : .regular)
                            FlowText(items: d.exercises.map { name in (name, name) }) { name in
                                if let ex = model.health.exercises.first(where: { $0.name == name }) { model.openExercise(ex) }
                            }
                        }
                        .padding(.vertical, 6)
                        .background(alignment: .leading) {
                            if today {
                                RoundedRectangle(cornerRadius: Theme.Radius.small).fill(Color.accentColor.opacity(0.1))
                                    .padding(.horizontal, -6)
                            }
                        }
                        if d.id != plan.days.last?.id { Divider().opacity(0.5).gridCellUnsizedAxes(.horizontal) }
                    }
                }
                .font(.callout)
                .padding(Theme.Space.m)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                if !plan.notes.isEmpty {
                    MarkdownBlocks(text: plan.notes).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 身体与测试

struct BodyAndTestsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let b = model.health.body
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "身体数据", systemImage: "figure.stand")
                Spacer()
                if let u = b.updated { Text("更新于 \(Fmt.shortDay(u))").font(.caption).foregroundStyle(.secondary) }
            }
            if b.fields.isEmpty {
                Text("还没有身体数据（健康/身体.md）。").foregroundStyle(.secondary)
            } else {
                // 三组并排：身体 / 力量 / 耐力，每组一列竖排，比平铺的方块整齐
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    ForEach(["身体", "力量", "耐力"], id: \.self) { group in
                        let items = b.fields.filter { HealthBody.group($0.key) == group }
                        VStack(alignment: .leading, spacing: 8) {
                            Label(group, systemImage: icon(group)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            if items.isEmpty { Text("—").foregroundStyle(.tertiary) }
                            ForEach(items) { m in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(HealthBody.label(m.key)).font(.caption).foregroundStyle(.secondary)
                                    Text(m.value).font(.callout.weight(.medium)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Theme.Space.m)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    }
                }
                let others = b.fields.filter { HealthBody.group($0.key) == "其他" }
                if !others.isEmpty {
                    Text(others.map { "\($0.key)：\($0.value)" }.joined(separator: "　")).font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HealthTestsPage()
                if let next = model.items.first(where: { $0.plugin == "health" && $0.title.contains("复测") && $0.start > model.clock }) {
                    Label("下一次复测：\(Fmt.day(next.start))", systemImage: "calendar.badge.clock").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func icon(_ group: String) -> String {
        switch group { case "身体": "figure.stand"; case "力量": "dumbbell"; default: "figure.run" }
    }
}

// MARK: - 动作

struct ExerciseListSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let exercises = model.health.exercises
        let plan = model.health.plan
        // 按一周计划里的顺序分组（同一个动作可以出现在两天）；计划里没有的放“其他”
        let groups: [(String, [Exercise])] = plan.days.compactMap { d in
            let list = d.exercises.compactMap { n in exercises.first { $0.name == n } }
            return list.isEmpty ? nil : ("\(d.weekday) · \(d.what)", list)
        }
        let listed = Set(groups.flatMap { $0.1.map(\.id) })
        let rest = exercises.filter { !listed.contains($0.id) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionTitle(text: "动作", systemImage: "dumbbell")
            if exercises.isEmpty { Text("还没有动作。").foregroundStyle(.secondary) }
            ForEach(Array((groups + (rest.isEmpty ? [] : [("其他", rest)])).enumerated()), id: \.offset) { _, g in
                VStack(alignment: .leading, spacing: 6) {
                    Text(g.0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: Theme.Space.s)], spacing: Theme.Space.s) {
                        ForEach(g.1) { ExerciseCard(exercise: $0) }
                    }
                }
            }
        }
    }
}

struct ExerciseCard: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        Button { model.openExercise(exercise) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(exercise.name).fontWeight(.semibold).lineLimit(1)
                    Spacer()
                    ForEach(exercise.primary.prefix(3), id: \.self) { k in
                        Circle().fill(MuscleStyle.color(k)).frame(width: 7, height: 7)
                    }
                }
                Text(exercise.nameEn).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(latest).font(.caption.monospacedDigit()).foregroundStyle(exercise.records.isEmpty ? .tertiary : .primary)
            }
            .padding(Theme.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var latest: String {
        if exercise.kind == .cardio { return "看训练记录" }
        guard let r = exercise.records.last else { return "目标 \(exercise.target) · 还没记录" }
        return "最近 \(Fmt.shortDay(r.date))：" + ExerciseFormat.record(r, exercise)
    }
}

enum ExerciseFormat {
    static func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    static func record(_ r: ExerciseRecord, _ ex: Exercise) -> String {
        var parts: [String] = []
        if let w = r.weight { parts.append("\(num(w)) \(ex.unit)") }
        if !r.repsText.isEmpty { parts.append("× \(r.repsText)") }
        if let s = r.sets { parts.append("· \(s) 组") }
        return parts.joined(separator: " ")
    }
}

struct ExerciseDetailView: View {
    @Environment(AppModel.self) private var model
    let exercise: Exercise

    var body: some View {
        let cal = model.calendar
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Button { model.openExerciseID = nil } label: { Label("健身与锻炼", systemImage: "chevron.left") }
                .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name).font(.largeTitle.bold())
                if !exercise.nameEn.isEmpty { Text(exercise.nameEn).font(.title3).foregroundStyle(.secondary) }
                HStack(spacing: Theme.Space.m) {
                    if !exercise.day.isEmpty { Label(exercise.day, systemImage: "calendar") }
                    if !exercise.target.isEmpty { Label("目标 \(exercise.target)", systemImage: "target") }
                    if !exercise.equipment.isEmpty { Label(exercise.equipment, systemImage: "dumbbell") }
                    if let s = exercise.step { Label("每次加 \(ExerciseFormat.num(s)) \(exercise.unit)", systemImage: "plus.circle") }
                }
                .font(.callout).foregroundStyle(.secondary)
                WrapLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(exercise.primary, id: \.self) { k in chip(k, primary: true) }
                    ForEach(exercise.secondary, id: \.self) { k in chip(k, primary: false) }
                }
            }

            if let hint = exercise.nextHint {
                Label(hint, systemImage: "arrow.up.forward.circle")
                    .font(.callout)
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }

            if exercise.kind == .cardio {
                cardioChart
            } else {
                progressChart(exercise.weeklyBests(calendar: cal))
                recordsTable
            }

            TripTextSection(title: "起始重量", icon: "flag", text: exercise.section("起始"))
            TripTextSection(title: "要点", icon: "checklist", text: exercise.section("要点"))
            TripTextSection(title: "建议", icon: "lightbulb", text: exercise.section("建议"))
            if !exercise.source.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: "来源", systemImage: "link")
                    ForEach(exercise.source.components(separatedBy: " "), id: \.self) { s in
                        if let url = URL(string: s), url.scheme != nil {
                            Link(s, destination: url).font(.caption)
                        }
                    }
                }
            }
        }
    }

    private func chip(_ key: String, primary: Bool) -> some View {
        let m = Muscle.named(key)
        let c = MuscleStyle.color(key)
        return Text((m?.zh ?? key) + (m.map { " \($0.en)" } ?? ""))
            .font(.caption.weight(primary ? .semibold : .regular))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(primary ? c.opacity(0.25) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(c.opacity(primary ? 0 : 0.7)))
            .help(primary ? "主要练到" : "辅助参与")
    }

    @ViewBuilder
    private func progressChart(_ bests: [WeeklyBest]) -> some View {
        let usesWeight = exercise.kind == .strength
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: usesWeight ? "每周最大负荷" : "每周最好成绩", systemImage: "chart.line.uptrend.xyaxis")
            if bests.isEmpty {
                Text("还没有记录。练完跟 agent 说一句（比如“卧推 70 lb，3 组都做了 8 个”），它会记到这个动作的“记录”表里。")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(bests) { b in
                    let y = usesWeight ? (b.record.weight ?? 0) : (b.record.reps ?? 0)
                    LineMark(x: .value("周", b.weekStart, unit: .weekOfYear), y: .value("值", y))
                    PointMark(x: .value("周", b.weekStart, unit: .weekOfYear), y: .value("值", y))
                        .annotation(position: .top) {
                            Text(usesWeight ? "\(ExerciseFormat.num(y))×\(b.record.repsText)" : b.record.repsText)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel(usesWeight ? exercise.unit : (exercise.kind == .timed ? "秒" : "次"))
                .frame(height: 180)
                if usesWeight, let first = bests.first?.record.estimated1RM, let last = bests.last?.record.estimated1RM, bests.count >= 2 {
                    Text("估算 1RM（Epley 公式）：\(ExerciseFormat.num(first)) → \(ExerciseFormat.num(last)) \(exercise.unit)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var recordsTable: some View {
        if !exercise.records.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "记录", systemImage: "list.bullet.rectangle")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow {
                        Text("日期"); Text("重量"); Text("次数"); Text("组数"); Text("备注")
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(exercise.records.reversed()) { r in
                        GridRow {
                            Text(Fmt.shortDay(r.date))
                            Text(r.weight.map { "\(ExerciseFormat.num($0)) \(exercise.unit)" } ?? "—")
                            Text(r.repsText.isEmpty ? "—" : r.repsText)
                            Text(r.sets.map(String.init) ?? "—")
                            Text(r.note).foregroundStyle(.secondary)
                        }
                        .monospacedDigit()
                    }
                }
                .font(.callout)
            }
        }
    }

    /// 跑步：用训练记录里的每周距离
    private var cardioChart: some View {
        let weeks = WeekStats.compute(model.health.sessions, calendar: model.calendar)
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "每周跑量", systemImage: "figure.run")
            if weeks.isEmpty {
                Text("还没有跑步记录（健康/训练记录/）。").font(.callout).foregroundStyle(.secondary)
            } else {
                Chart(weeks, id: \.weekStart) { w in
                    BarMark(x: .value("周", w.weekStart, unit: .weekOfYear), y: .value("km", w.runKm))
                        .annotation(position: .top) { Text(String(format: "%.1f", w.runKm)).font(.caption2).foregroundStyle(.secondary) }
                }
                .frame(height: 160)
                if let pace = weeks.last?.pace {
                    Text("最近一周平均配速 \(HealthFormat.minutesText(pace)) /km").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 健身与锻炼页

/// 健身与锻炼页：记录（日 / 周 / 月）/ 长期趋势（每周变化 + 归档）/ 计划与动作（肌肉图、一周计划、身体与复测、动作）
struct FitnessView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("fitnessTab") private var tab = FitnessTab.records.rawValue
    @AppStorage("fitnessScale") private var scale = HealthPeriod.Scale.week.rawValue
    @State private var anchor = Date()

    enum FitnessTab: String, CaseIterable, Identifiable {
        case records, trend, plan
        var id: String { rawValue }
        var label: String {
            switch self { case .records: "记录"; case .trend: "长期趋势"; case .plan: "计划与动作" }
        }
    }

    var body: some View {
        let current = FitnessTab(rawValue: tab) ?? .records
        let period = HealthPeriod(scale: HealthPeriod.Scale(rawValue: scale) ?? .week, anchor: anchor)
        HealthPageScaffold(title: "健身与锻炼") {
            // 打开了某个动作：整页给动作详情
            if current == .plan, model.openExerciseID != nil {
                FitnessPage()
            } else {
                TabStrip(tabs: FitnessTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
                switch current {
                case .records:
                    HealthPeriodBar(period: Binding(get: { period }, set: { scale = $0.scale.rawValue; anchor = $0.anchor }))
                    switch period.scale {
                    case .day: FitnessDayPage(day: anchor)
                    case .week, .month:
                        FitnessRangePage(period: period) { d in anchor = d; scale = HealthPeriod.Scale.day.rawValue }
                    }
                case .trend: HealthLogPage()
                case .plan: FitnessPage()
                }
            }
        }
        // 换到别的分页 / 别的页才收起动作详情（打开动作时会把分页写成 plan，那次不算）
        .onChange(of: tab) { if tab != FitnessTab.plan.rawValue { model.openExerciseID = nil } }
        .onChange(of: model.page) { if model.page != .fitness { model.openExerciseID = nil } }
    }
}

/// 健身 · 日：计划练什么 + 实际练了什么 + 记一笔
struct FitnessDayPage: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let cal = model.calendar
        let planned = model.training(on: day)
        let iv = HealthPeriod(scale: .day, anchor: day).interval(calendar: cal)
        let summary = model.health.fitnessSummary(in: iv, calendar: cal)
        let future = cal.startOfDay(for: day) > cal.startOfDay(for: model.clock)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if !summary.sessions.isEmpty {
                StatRow {
                    StatTile(title: "训练", value: "\(summary.sessions.count) 次")
                    StatTile(title: "训练量", value: summary.volume > 0 ? "\(Int(summary.volume)) lb×次" : "—")
                    StatTile(title: "跑步", value: summary.runKm > 0 ? String(format: "%.1f km", summary.runKm) : "—")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "计划", systemImage: "calendar")
                if planned.isEmpty {
                    Text("这天没有安排训练。").foregroundStyle(.secondary)
                } else {
                    ForEach(planned, id: \.occurrence.id) { t in
                        TrainingSummary(occurrence: t.occurrence, item: t.item, maxRows: 8)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "实际练了", systemImage: "checkmark.circle")
                if summary.sessions.isEmpty {
                    Text(future ? "还没到这天。" : "这天还没有训练记录。").foregroundStyle(.secondary)
                } else {
                    ForEach(summary.sessions) { s in SessionRow(session: s) }
                }
            }

            if !future { WorkoutNoteField(day: day) }
        }
    }
}

/// 记一笔练了什么：放进收件箱，agent 整理成训练记录和动作记录（组次的格式要求多，App 不直接写）
struct WorkoutNoteField: View {
    @Environment(AppModel.self) private var model
    let day: Date
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField("记一笔练了什么，比如“卧推 75 lb 3×12，划船 70 lb 3×10”", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("记下", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("会放进收件箱，agent 整理进训练记录和每个动作的记录。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        model.capture("训练 \(Fmt.string(day, "M/d"))：\(t)", message: "已记进收件箱，等 agent 整理进训练记录")
        draft = ""
    }
}

/// 健身 · 周 / 月：次数、天数、里程、训练量，计划和实际对照，按天的图，这段时间的每一次
struct FitnessRangePage: View {
    @Environment(AppModel.self) private var model
    let period: HealthPeriod
    let onSelectDay: (Date) -> Void

    var body: some View {
        let cal = model.calendar
        let days = period.days(calendar: cal)
        let summary = model.health.fitnessSummary(in: period.interval(calendar: cal), calendar: cal)
        let planned = days.filter { !model.training(on: $0).isEmpty }.count
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            StatRow {
                StatTile(title: "训练", value: "\(summary.sessions.count) 次")
                StatTile(title: "练了", value: "\(summary.activeDays) / \(planned) 天（计划）")
                StatTile(title: "跑步", value: String(format: "%.1f km", summary.runKm))
                StatTile(title: "训练量", value: "\(Int(summary.volume)) lb×次")
            }
            if let pace = summary.pace {
                Text("平均配速 \(HealthFormat.minutesText(pace)) /km").font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "计划和实际", systemImage: "calendar.badge.checkmark")
                if period.scale == .week {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(days, id: \.self) { d in dayChip(d) }
                    }
                } else {
                    MonthHeatGrid(days: days, color: Theme.green, cell: heat, onSelect: onSelectDay)
                }
                Text("绿 = 练了；“计划” = 安排了但没有训练记录。点一天看那天。").font(.caption).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "每天", systemImage: "chart.bar")
                HStack(spacing: Theme.Space.l) {
                    DailyBarChart(title: "力量训练量（lb×次）", points: points(days) { $0.compactMap(\.volume).reduce(0, +) }, color: Theme.green)
                    if summary.runKm > 0 {
                        DailyBarChart(title: "跑步（km）", points: points(days) { $0.compactMap(\.distanceKm).reduce(0, +) },
                                      color: Theme.blue, axisLabel: { String(format: "%.0f", $0) })
                    }
                }
            }

            if !summary.sessions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "这段时间的训练（\(summary.sessions.count) 次）", systemImage: "list.bullet")
                    ForEach(summary.sessions.reversed()) { s in SessionRow(session: s) }
                }
            }
        }
    }

    private func sessions(on d: Date) -> [HealthSession] {
        model.health.sessions.filter { model.calendar.isDate($0.date, inSameDayAs: d) }
    }

    private func points(_ days: [Date], _ value: ([HealthSession]) -> Double) -> [DailyBarChart.Point] {
        days.map { .init(day: $0, value: value(sessions(on: $0))) }
    }

    private func heat(_ d: Date) -> HeatCell {
        let done = sessions(on: d)
        if !done.isEmpty {
            let text = done.map { $0.kind == .run ? "跑" : "练" }.joined()
            return HeatCell(fraction: 1, text: text)
        }
        return model.training(on: d).isEmpty ? HeatCell() : HeatCell(fraction: nil, text: "计划")
    }

    /// 周视图一天一个小块：星期 + 练了 / 计划 / 休息
    private func dayChip(_ d: Date) -> some View {
        let cal = model.calendar
        let done = sessions(on: d)
        let plan = model.training(on: d)
        let past = cal.startOfDay(for: d) < cal.startOfDay(for: model.clock)
        let label = !done.isEmpty ? "练了" : (plan.isEmpty ? "休息" : (past ? "没练" : "计划"))
        let icon = !done.isEmpty ? "checkmark.circle.fill" : (plan.isEmpty ? "moon" : "circle.dashed")
        return Button { onSelectDay(d) } label: {
            VStack(spacing: 4) {
                Text(Fmt.string(d, "EEE")).font(.caption).foregroundStyle(.secondary)
                Image(systemName: icon).font(.title3).foregroundStyle(done.isEmpty ? Color.secondary : Theme.green)
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(.quaternary.opacity(cal.isDate(d, inSameDayAs: model.clock) ? 0.9 : 0.4),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}
