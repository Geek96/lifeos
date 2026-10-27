import SwiftUI
import AppKit
import LifeOSCore

// 远景插件：愿景（时间甬道 / 清单）、项目（步骤与进度）、奇思妙想（卡片墙）。
// 内容由 agent 维护；App 里能做的只有勾项目步骤。

struct VisionView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("visionTab") private var tab = VisionTab.visions.rawValue

    enum VisionTab: String, CaseIterable, Identifiable {
        case visions, projects, ideas
        var id: String { rawValue }
        var label: String {
            switch self { case .visions: "愿景"; case .projects: "项目"; case .ideas: "奇思妙想" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let id = model.openIdeaID, let idea = model.vision.ideas.first(where: { $0.id == id }) {
                    IdeaDetailView(idea: idea)
                } else if let id = model.openProjectID, let p = model.vision.projects.first(where: { $0.id == id }) {
                    ProjectDetailView(project: p)
                } else if let id = model.openVisionID, let v = model.vision.visions.first(where: { $0.id == id }) {
                    VisionDetailView(vision: v)
                } else {
                    Text("远景").font(.largeTitle.bold())
                    TabStrip(tabs: VisionTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
                    switch VisionTab(rawValue: tab) ?? .visions {
                    case .visions: VisionsPage()
                    case .projects: ProjectsPage()
                    case .ideas: IdeasPage()
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.page) {
            if model.page != .vision {
                model.openVisionID = nil
                model.openProjectID = nil
                model.openIdeaID = nil
            }
        }
    }
}

// MARK: - 愿景

struct VisionsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if model.vision.visions.isEmpty {
                Text("还没有愿景。").foregroundStyle(.secondary)
            }
            ForEach(model.vision.visions) { VisionCard(vision: $0) }
        }
    }
}

struct VisionCard: View {
    @Environment(AppModel.self) private var model
    let vision: Vision

    var body: some View {
        let projects = model.vision.projects(of: vision)
        Button { model.openVision(vision) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack(spacing: 6) {
                    Text(vision.title).font(.title3.weight(.semibold))
                    VisionPill(text: vision.status)
                    Spacer()
                    if !projects.isEmpty {
                        Text("\(projects.count) 个项目").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !vision.summary.isEmpty { Text(vision.summary).foregroundStyle(.secondary).lineLimit(2) }
                switch vision.shape {
                case .timeline:
                    VisionCorridor(vision: vision, compact: true)
                    if let next = vision.nextCheckpoint(now: model.clock) {
                        Label("下一个：\(next.when) · \(next.text)", systemImage: "flag")
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                case .list:
                    let visited = vision.places.filter(\.visited)
                    HStack(spacing: Theme.Space.s) {
                        Text("去过 \(visited.count) · 想去 \(vision.places.count - visited.count)")
                            .font(.callout.weight(.medium))
                        Spacer()
                        ForEach(visited.compactMap(\.photos.first).prefix(4), id: \.self) { url in
                            PlacePhoto(url: url, width: 44, height: 44)
                        }
                    }
                }
            }
            .padding(Theme.Space.m)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 时间甬道：起点到目标，checkpoint（模糊时间画成一小段）、今天的位置
struct VisionCorridor: View {
    @Environment(AppModel.self) private var model
    let vision: Vision
    var compact = false

    private let labelWidth: CGFloat = 116
    private let trackY: CGFloat = 22
    private let rowHeight: CGFloat = 40

    var body: some View {
        if let span = vision.span(calendar: model.calendar) {
            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    HStack {
                        Text(vision.start.isEmpty ? Fmt.shortDay(span.start) : "起点 \(vision.start)")
                        Spacer()
                        Text(vision.target.isEmpty ? Fmt.shortDay(span.end) : "目标 \(vision.target)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                let marks = vision.checkpoints.filter { $0.interval != nil }
                GeometryReader { geo in
                    let w = geo.size.width
                    let rows = compact ? [:] : labelRows(marks, span: span, width: w)
                    ZStack(alignment: .topLeading) {
                        Capsule().fill(.quaternary).frame(width: w, height: 6).offset(y: trackY - 3)
                        Capsule().fill(Color.accentColor.opacity(0.35))
                            .frame(width: x(model.clock, span, w), height: 6).offset(y: trackY - 3)
                        ForEach(marks) { c in
                            let iv = c.interval!
                            let x0 = x(iv.start, span, w), x1 = x(iv.end, span, w)
                            let segW = max(12, x1 - x0)
                            let left = min(max(0, (x0 + x1) / 2 - segW / 2), w - segW)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(fill(c))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(stroke(c), lineWidth: 1.5))
                                .frame(width: segW, height: 12)
                                .offset(x: left, y: trackY - 6)
                                .help("\(c.when) · \(c.text)" + (c.result == .none ? "" : " · \(c.result.rawValue)"))
                            if let row = rows[c.id] {
                                let center = (x0 + x1) / 2
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.when).font(.caption2).foregroundStyle(.secondary)
                                    Text(c.text).font(.caption).lineLimit(2)
                                }
                                .frame(width: labelWidth, alignment: .leading)
                                .offset(x: min(max(0, center - 6), w - labelWidth), y: trackY + 12 + CGFloat(row) * rowHeight)
                            }
                        }
                        let tx = x(model.clock, span, w)
                        Rectangle().fill(.primary.opacity(0.8)).frame(width: 2, height: 20).offset(x: tx - 1, y: trackY - 10)
                        if !compact {
                            Text("今天").font(.caption2.weight(.semibold))
                                .offset(x: min(max(0, tx - 12), w - 28), y: 0)
                        }
                    }
                }
                .frame(height: compact ? trackY + 12 : trackY + 12 + rowHeight * CGFloat(max(1, labelRowCount(marks, span: span))))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        } else {
            Text("还没有能画在时间轴上的时间（起点、目标或 checkpoint 写成“2026-12 中旬”“2027 夏”这样）")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func x(_ d: Date, _ span: DateInterval, _ w: CGFloat) -> CGFloat {
        CGFloat(max(0, min(1, d.timeIntervalSince(span.start) / span.duration))) * w
    }

    /// 标签分行：每行从左往右放，放不下就换到下一行；三行都放不下的不显示标签（下面的列表里有）
    private func labelRows(_ marks: [Checkpoint], span: DateInterval, width: CGFloat) -> [Int: Int] {
        var rowEnds: [CGFloat] = [-.infinity, -.infinity, -.infinity]
        var out: [Int: Int] = [:]
        for c in marks.sorted(by: { $0.interval!.start < $1.interval!.start }) {
            let iv = c.interval!
            let center = (x(iv.start, span, width) + x(iv.end, span, width)) / 2
            let left = min(max(0, center - 6), width - labelWidth)
            if let r = rowEnds.firstIndex(where: { $0 + 8 <= left }) {
                out[c.id] = r
                rowEnds[r] = left + labelWidth
            }
        }
        return out
    }

    private func labelRowCount(_ marks: [Checkpoint], span: DateInterval) -> Int {
        // 实际宽度在 GeometryReader 里才知道：按偏窄的 560pt 估算，宁可多留一点空
        (labelRows(marks, span: span, width: 560).values.max() ?? 0) + 1
    }

    private func fill(_ c: Checkpoint) -> Color {
        switch c.result {
        case .reached: Theme.green
        case .partly: Theme.orange
        case .missed: Theme.red.opacity(0.7)
        case .changed: Theme.blue.opacity(0.6)
        case .none: (c.interval!.end < model.clock) ? Color.secondary.opacity(0.5) : Color.accentColor.opacity(0.2)
        }
    }

    private func stroke(_ c: Checkpoint) -> Color {
        c.result == .none && c.interval!.end >= model.clock ? Color.accentColor : .clear
    }

    private var accessibilityText: String {
        let parts = vision.checkpoints.map { "\($0.when) \($0.text)" + ($0.result == .none ? "" : "，\($0.result.rawValue)") }
        return "时间甬道：" + parts.joined(separator: "；")
    }
}

struct VisionDetailView: View {
    @Environment(AppModel.self) private var model
    let vision: Vision

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack {
                Button { model.openVisionID = nil } label: { Label("远景", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(vision.title).font(.largeTitle.bold())
                    VisionPill(text: vision.status)
                }
                if !vision.summary.isEmpty { Text(vision.summary).font(.title3).foregroundStyle(.secondary) }
                if !vision.tags.isEmpty { TagRow(tags: vision.tags) }
            }

            switch vision.shape {
            case .timeline:
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "时间甬道", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    VisionCorridor(vision: vision)
                    CheckpointList(vision: vision)
                }
            case .list:
                PlaceWall(vision: vision)
            }

            TripTextSection(title: "为什么", icon: "heart", text: vision.section("为什么"))
            TripTextSection(title: "详细愿景", icon: "sparkles", text: vision.section("详细愿景"))
            TripTextSection(title: "路线规划", icon: "map", text: vision.section("路线规划"))

            let projects = model.vision.projects(of: vision)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "相关项目", systemImage: "hammer")
                if projects.isEmpty {
                    Text("还没有挂在这个愿景下的项目。").foregroundStyle(.secondary)
                }
                ForEach(projects) { ProjectCard(project: $0, showVision: false) }
            }
        }
    }
}

struct CheckpointList: View {
    @Environment(AppModel.self) private var model
    let vision: Vision

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vision.checkpoints) { c in
                let past = (c.interval?.end).map { $0 < model.clock } ?? false
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Text(c.when).monospacedDigit().foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.text)
                        if !c.note.isEmpty { Text(c.note).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    if c.result != .none {
                        Text(c.result.rawValue).font(.caption.weight(.medium)).tagCapsule(resultColor(c.result), horizontal: 7, vertical: 2)
                    } else if past {
                        Text("过了，还没标").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
    }

    private func resultColor(_ r: Checkpoint.Result) -> Color {
        switch r {
        case .reached: Theme.green
        case .partly: Theme.orange
        case .missed: Theme.red
        case .changed: Theme.blue
        case .none: .secondary
        }
    }
}

/// 清单型愿景：平铺的条目 + 标签筛选；去过的亮，想去的灰着
struct PlaceWall: View {
    @Environment(AppModel.self) private var model
    let vision: Vision
    @State private var filter: String?

    var body: some View {
        let visited = vision.places.filter(\.visited).count
        let tags = tagCounts.map(\.0)
        let shown = vision.places.filter { p in
            switch filter {
            case nil: true
            case "去过"?: p.visited
            case "想去"?: !p.visited
            case let t?: p.tags.contains(t)
            }
        }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionTitle(text: "去过 \(visited) · 想去 \(vision.places.count - visited)", systemImage: "mappin.and.ellipse")
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach([nil, "去过", "想去"] + tags.map { Optional($0) }, id: \.self) { t in
                        FilterChip(text: t ?? "全部", on: filter == t) { filter = t }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(shown) { p in
                    let trip = model.trip(for: p)
                    Button {
                        if let trip { model.openTrip(trip, from: vision) }
                    } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        // 自己拍的照片优先，没有就用行程的封面
                        PlacePhoto(url: p.photos.first ?? trip?.cover, width: nil, height: 110)
                            .saturation(p.visited ? 1 : 0)
                        HStack(spacing: 6) {
                            Text(p.name).font(.headline).lineLimit(1)
                            if !p.visited { Text("想去").font(.caption).foregroundStyle(.secondary) }
                        }
                        if !p.when.isEmpty { Label(p.when, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                        if !p.tags.isEmpty { Text(p.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        if !p.note.isEmpty { Text(p.note).font(.caption).lineLimit(2) }
                        if trip != nil {
                            Label("打开行程", systemImage: "arrow.right.circle")
                                .font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(Theme.Space.s)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.quaternary.opacity(p.visited ? 0.5 : 0.25), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    .opacity(p.visited ? 1 : 0.75)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(trip == nil)
                }
            }
            if vision.places.isEmpty {
                Text("清单还是空的。").foregroundStyle(.secondary)
            }
        }
    }

    /// 标签按出现次数排
    private var tagCounts: [(String, Int)] {
        var counts: [String: Int] = [:]
        for p in vision.places { for t in p.tags { counts[t, default: 0] += 1 } }
        return counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
    }
}

struct PlacePhoto: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.teal.opacity(0.2), Theme.purple.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .allowsHitTesting(false)  // 同 CoverImage：超出边框的部分别挡住别的按钮
    }
}

// MARK: - 项目

struct ProjectsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snap = model.vision
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                Text("每个项目是一件能做完的事；可以挂在某个愿景下，也可以单独存在。").foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(snap.visions) { v in
                let ps = snap.projects(of: v)
                if !ps.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Button { model.openVision(v) } label: {
                            SectionTitle(text: v.title, systemImage: "mountain.2")
                        }
                        .buttonStyle(.plain)
                        ForEach(ps) { ProjectCard(project: $0, showVision: false) }
                    }
                }
            }
            if !snap.unfiledProjects.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "未归类", systemImage: "tray")
                    ForEach(snap.unfiledProjects) { ProjectCard(project: $0, showVision: false) }
                }
            }
            if snap.projects.isEmpty {
                Text("还没有项目。").foregroundStyle(.secondary)
            }
        }
    }
}

struct ProjectCard: View {
    @Environment(AppModel.self) private var model
    let project: VisionProject
    var showVision = true

    var body: some View {
        Button { model.openProject(project) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer").foregroundStyle(.secondary)
                    Text(project.title).font(.body.weight(.semibold)).lineLimit(1)
                    VisionPill(text: project.status)
                    if showVision && !project.vision.isEmpty {
                        Text(project.vision).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !project.steps.isEmpty {
                        Text("\(project.doneCount)/\(project.steps.count)").font(.callout.weight(.medium)).monospacedDigit()
                    }
                }
                if !project.goal.isEmpty { Text(project.goal).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                if !project.steps.isEmpty { ProgressStrip(value: project.progress) }
                HStack {
                    if let next = project.nextStep {
                        Text("下一步：\(next.text)" + (next.date.map { " · \(Fmt.shortDay($0))" } ?? "")).lineLimit(1)
                    } else if !project.steps.isEmpty {
                        Text("步骤都做完了").foregroundStyle(Theme.green)
                    } else {
                        Text("还没拆步骤").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !project.target.isEmpty { Text("目标 \(project.target)").foregroundStyle(.secondary) }
                }
                .font(.caption)
            }
            .padding(Theme.Space.m)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .opacity(project.isClosed ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 完成进度条
struct ProgressStrip: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(Theme.green.gradient).frame(width: max(0, geo.size.width * value))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("完成 \(Int((value * 100).rounded()))%")
    }
}

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    let project: VisionProject

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack {
                Button { model.openProjectID = nil } label: {
                    Label(model.openVisionID == nil ? "远景" : "愿景", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.title).font(.largeTitle.bold())
                    VisionPill(text: project.status)
                }
                if !project.goal.isEmpty { Text(project.goal).font(.title3).foregroundStyle(.secondary) }
                HStack(spacing: Theme.Space.m) {
                    if let v = model.vision.visions.first(where: { $0.title == project.vision }) {
                        Button { model.openVision(v) } label: { Label(v.title, systemImage: "mountain.2") }
                            .buttonStyle(.link)
                    } else {
                        Label("未归类", systemImage: "tray").foregroundStyle(.secondary)
                    }
                    if !project.start.isEmpty || !project.target.isEmpty {
                        Label([project.start, project.target].filter { !$0.isEmpty }.joined(separator: " → "), systemImage: "calendar")
                            .foregroundStyle(.secondary)
                    }
                    if let idea = model.vision.ideas.first(where: { $0.title == project.fromIdea }) {
                        Button { model.openIdea(idea) } label: { Label("来自想法：\(idea.title)", systemImage: "lightbulb") }
                            .buttonStyle(.link)
                    }
                }
                .font(.callout)
                if !project.tags.isEmpty { TagRow(tags: project.tags) }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    SectionTitle(text: "步骤", systemImage: "checklist")
                    Spacer()
                    if !project.steps.isEmpty {
                        Text("\(project.doneCount) / \(project.steps.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if project.steps.isEmpty {
                    Text("还没拆步骤。").foregroundStyle(.secondary)
                } else {
                    ProgressStrip(value: project.progress)
                    ForEach(project.steps) { step in
                        Button { model.toggleStep(step, in: project) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(step.done ? Theme.green : .secondary)
                                Text(step.text).strikethrough(step.done).foregroundStyle(step.done ? .secondary : .primary)
                                Spacer()
                                if let d = step.date {
                                    Text(step.hasTime ? "\(Fmt.shortDay(d)) \(Fmt.time(d))" : Fmt.shortDay(d))
                                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !project.log.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "进展记录", systemImage: "text.book.closed")
                    ForEach(Array(project.log.enumerated().reversed()), id: \.offset) { _, entry in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                            Text(entry.date).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Text(TripTextSection.render(entry.text)).textSelection(.enabled)
                        }
                        .font(.callout)
                    }
                }
            }
            TripTextSection(title: "说明", icon: "text.alignleft", text: project.section("说明"))
        }
    }
}

// MARK: - 奇思妙想

struct IdeasPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage("ideaFilter") private var filter = ""

    var body: some View {
        let ideas = model.vision.ideas
        let present = Set(ideas.map(\.category))
        let categories = Idea.categories.filter(present.contains) + present.subtracting(Idea.categories).sorted()
        let shown = filter.isEmpty ? ideas : ideas.filter { $0.category == filter }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 6) {
                FilterChip(text: "全部 \(ideas.count)", on: filter.isEmpty) { filter = "" }
                ForEach(categories, id: \.self) { c in
                    FilterChip(text: "\(c) \(ideas.filter { $0.category == c }.count)", on: filter == c) { filter = c }
                }
                Spacer()
                Button {
                    if let pick = shown.randomElement() { model.openIdea(pick) }
                } label: { Label("随机翻一条", systemImage: "shuffle") }
                .disabled(shown.isEmpty)
            }
            if ideas.isEmpty {
                Text("还没有想法。").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(shown) { IdeaCard(idea: $0) }
            }
        }
        .onAppear { if !filter.isEmpty && !present.contains(filter) { filter = "" } }
    }
}

struct IdeaCard: View {
    @Environment(AppModel.self) private var model
    let idea: Idea

    var body: some View {
        Button { model.openIdea(idea) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Label(idea.category, systemImage: IdeaStyle.icon(idea.category))
                        .font(.caption.weight(.medium)).foregroundStyle(IdeaStyle.color(idea.category))
                    Spacer()
                    if idea.status != "随想" { VisionPill(text: idea.status) }
                }
                Text(idea.title).font(.headline).lineLimit(2)
                if !idea.excerpt.isEmpty && idea.excerpt != idea.title {
                    Text(idea.excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                HStack {
                    if let d = idea.created { Text(Fmt.shortDay(d)) }
                    if !idea.tags.isEmpty { Text(idea.tags.joined(separator: " · ")).lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(Theme.Space.m)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
            .background(IdeaStyle.color(idea.category).opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .opacity(idea.status.contains("放下") ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct IdeaDetailView: View {
    @Environment(AppModel.self) private var model
    let idea: Idea

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack {
                Button { model.openIdeaID = nil } label: { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(idea.category, systemImage: IdeaStyle.icon(idea.category))
                    .font(.callout.weight(.medium)).foregroundStyle(IdeaStyle.color(idea.category))
                HStack(spacing: 8) {
                    Text(idea.title).font(.largeTitle.bold())
                    VisionPill(text: idea.status)
                }
                HStack(spacing: Theme.Space.m) {
                    if let d = idea.created { Label("记于 \(Fmt.shortDay(d))", systemImage: "calendar").foregroundStyle(.secondary) }
                    if let v = model.vision.visions.first(where: { $0.title == idea.vision }) {
                        Button { model.openVision(v) } label: { Label(v.title, systemImage: "mountain.2") }.buttonStyle(.link)
                    }
                    if let p = model.vision.projects.first(where: { $0.title == idea.project }) {
                        Button { model.openProject(p) } label: { Label("项目：\(p.title)", systemImage: "hammer") }.buttonStyle(.link)
                    }
                }
                .font(.callout)
                if !idea.tags.isEmpty { TagRow(tags: idea.tags) }
            }

            TripTextSection(title: "内容", icon: "text.alignleft", text: IdeaStyle.flatten(idea.body))
        }
    }
}

enum IdeaStyle {
    static func icon(_ category: String) -> String {
        switch category {
        case "软件": "app.badge"
        case "Skill": "wand.and.stars"
        case "创作": "film"
        case "研究": "magnifyingglass"
        case "体验": "figure.walk"
        case "随想": "bubble.left"
        default: "lightbulb"
        }
    }

    static func color(_ category: String) -> Color {
        switch category {
        case "软件": Theme.blue
        case "Skill": Theme.indigo
        case "创作": Theme.purple
        case "研究": Theme.teal
        case "体验": Theme.green
        case "随想": Theme.orange
        default: .secondary
        }
    }

    /// 正文里的 `## 小标题` 变成加粗的一行
    static func flatten(_ body: String) -> String {
        body.components(separatedBy: "\n").map { line in
            line.hasPrefix("#") ? "**" + line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) + "**" : line
        }.joined(separator: "\n")
    }
}

// MARK: - 小部件

struct VisionPill: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text).font(.caption.weight(.medium)).tagCapsule(color, horizontal: 7, vertical: 2)
        }
    }
    private var color: Color {
        if ["进行中", "在琢磨"].contains(where: text.contains) { return Theme.blue }
        if ["实现", "做完", "已变成项目"].contains(where: text.contains) { return Theme.green }
        if ["搁置", "暂停"].contains(where: text.contains) { return Theme.orange }
        if text.contains("放下") { return .secondary }
        return Theme.purple
    }
}

struct TagRow: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { Text("#\($0)").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct FilterChip: View {
    let text: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.callout.weight(on ? .semibold : .regular))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(on ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: Capsule())
                .foregroundStyle(on ? Color.accentColor : .primary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - 右栏

/// 日历上点到项目的一步
struct ProjectOccurrenceDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let project: VisionProject

    var body: some View {
        let line = occurrence.id.split(separator: "#").last.flatMap { Int($0) }
        let step = project.steps.first { $0.line == line }
        DetailHeader(occurrence: occurrence)
        VStack(alignment: .leading, spacing: 6) {
            Label(project.title, systemImage: "hammer")
            if !project.vision.isEmpty { Label(project.vision, systemImage: "mountain.2").foregroundStyle(.secondary) }
            if !project.steps.isEmpty {
                Text("项目进度 \(project.doneCount)/\(project.steps.count)").foregroundStyle(.secondary)
                ProgressStrip(value: project.progress)
            }
        }
        .font(.callout)
        HStack {
            if let step {
                Button(step.done ? "标成没做完" : "做完了") { model.toggleStep(step, in: project) }
            }
            Button("打开项目") { model.openProject(project) }
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}
