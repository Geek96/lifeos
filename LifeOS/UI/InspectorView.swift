import SwiftUI
import LifeOSCore

/// 右栏：选中一件事 → 详情、提示、空档、准备信息；没选 → 这周概况 + agent 最近做了什么。
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if let o = model.selected {
                    if let item = model.item(for: o) {
                        LifeDetail(occurrence: o, item: item)
                    } else if let thing = model.thing(for: o) {
                        ThingOccurrenceDetail(occurrence: o, thing: thing)
                    } else if let trip = model.trip(for: o) {
                        TripOccurrenceDetail(occurrence: o, trip: trip)
                    } else if let project = model.project(for: o) {
                        ProjectOccurrenceDetail(occurrence: o, project: project)
                    } else if o.id.hasPrefix("finance:") {
                        FinanceOccurrenceDetail(occurrence: o)
                    } else {
                        CourseDetail(occurrence: o)
                    }
                } else {
                    Overview()
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 详情头：类型标签 + 标题 + 时间
struct DetailHeader: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusTag(text: occurrence.style.label, systemImage: Theme.icon(occurrence.style), tint: Theme.tint(occurrence.style))
            Text(occurrence.title).font(.title3.bold()).textSelection(.enabled)
            Label(Fmt.day(occurrence.start) + " · " + Fmt.when(occurrence, now: model.clock, calendar: model.calendar),
                  systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }
}

struct LifeDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let item: LifeItem

    var body: some View {
        DetailHeader(occurrence: occurrence)
        VStack(alignment: .leading, spacing: 6) {
            if !item.location.isEmpty { Label(item.location, systemImage: "mappin.and.ellipse").textSelection(.enabled) }
            if let r = item.repeatRule {
                Label(r.label + (item.repeatUntil.map { "，到 \(Fmt.shortDay($0))" } ?? ""), systemImage: "repeat")
            }
            if item.kind == .window, let h = item.estimateHours { Label("大概要 \(Fmt.hours(h))", systemImage: "hourglass") }
            if item.kind == .deadline { Label("提前 \(item.remindDays) 天出现在“快到了”", systemImage: "bell") }
            if item.addedBy == "agent" { Label("agent 添加", systemImage: "sparkles") }
        }
        .font(.callout)

        let hints = model.hints(for: occurrence)
        if !hints.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(hints, id: \.self) { h in
                    Label(h.text, systemImage: h.tone == .caution ? "exclamationmark.triangle" : "info.circle")
                        .foregroundStyle(h.tone == .caution ? Theme.orange : .secondary)
                        .font(.callout)
                }
            }
            .card()
        }

        if item.kind == .window && !item.done {
            let slots = model.freeSlots(for: item)
            VStack(alignment: .leading, spacing: 6) {
                Text("可以安排在").font(.headline)
                if slots.isEmpty {
                    Text("窗口里找不到够长的空档。").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(slots, id: \.self) { slot in
                    HStack {
                        Text("\(Fmt.relativeDay(slot.interval.start, now: model.clock, calendar: model.calendar)) \(Fmt.time(slot.interval.start))–\(Fmt.time(slot.interval.end))")
                            .monospacedDigit()
                        Spacer()
                        Button("排进去") {
                            model.create(kind: .event, title: item.title, start: slot.interval.start, end: slot.interval.end,
                                         hasTime: true, location: item.location, repeatRule: nil, estimate: nil)
                        }
                        .controlSize(.small)
                        .help("新建一个同名约定放在这个时间")
                    }
                    .font(.callout)
                }
            }
            .card()
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("准备信息").font(.headline)
            if item.body.isEmpty {
                Text("还没有。").font(.callout).foregroundStyle(.secondary)
            } else {
                MarkdownBlocks(text: item.body).font(.callout)
            }
        }

        Divider()
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("编辑…") { model.edit(item) }
                if item.kind != .event && item.repeatRule == nil {
                    Button(item.done ? "恢复" : "办好了") { model.toggleDone(item) }
                        .help(item.done ? "恢复成未办" : "收起来；不点也只会自然淡出")
                }
            }
            Button("在访达中显示") { model.reveal(item.fileURL) }
                .buttonStyle(.link)
            Button("移到废纸篓", role: .destructive) { model.trash(item) }
                .buttonStyle(.link)
                .foregroundStyle(Theme.red)
        }
        .font(.callout)
    }
}

/// 课程图层的事：只读，来自 CourseOS
struct CourseDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence

    var body: some View {
        DetailHeader(occurrence: occurrence)
        VStack(alignment: .leading, spacing: 6) {
            if let c = occurrence.course { Label(c, systemImage: "graduationcap") }
            if !occurrence.location.isEmpty { Label(occurrence.location, systemImage: "mappin.and.ellipse") }
            if let w = occurrence.workloadHours { Label("预估 \(Fmt.hours(w))（摊到前几天算进负荷）", systemImage: "hourglass") }
            if occurrence.done { Label("CourseOS 里已完成", systemImage: "checkmark.circle").foregroundStyle(Theme.green) }
        }
        .font(.callout)
        Text("来自 CourseOS，只读。完成、忽略等操作请在 CourseOS 里做。")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            if let url = occurrence.sourceURL {
                Button("打开原页面") { model.openWeb(url) }
            }
            Button("打开 CourseOS") {
                if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.geek96.courseos") {
                    NSWorkspace.shared.openApplication(at: app, configuration: .init())
                } else {
                    model.feedback.show("没找到 CourseOS App")
                }
            }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}

/// 没选中时：这周概况、快到了、agent 最近动态
struct Overview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let week = DateInterval(start: cal.startOfDay(for: model.clock), duration: 7 * 86400)
        let loads = model.loads(for: week)
        let busy = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
            .filter { loads[$0]?.level == .busy }
        let light = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
            .filter { (loads[$0]?.level ?? .light) == .light }

        VStack(alignment: .leading, spacing: 8) {
            Text("接下来 7 天").font(.headline)
            if !busy.isEmpty {
                Label("比较满：" + busy.map { Fmt.relativeDay($0, now: model.clock, calendar: cal) }.joined(separator: "、"),
                      systemImage: "circle.fill").foregroundStyle(Theme.orange)
            }
            if !light.isEmpty {
                Label("适合办事：" + light.map { Fmt.relativeDay($0, now: model.clock, calendar: cal) }.joined(separator: "、"),
                      systemImage: "circle.fill").foregroundStyle(Theme.green)
            }
            Text("负荷 = 上课 + 约定 + 课业（课程截止的预估工作量摊到截止前几天）。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .font(.callout)
        .card()

        if !model.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("快到了").font(.headline)
                ForEach(model.upcoming) { o in
                    OccurrenceRow(occurrence: o, includeDay: true)
                        .onTapGesture { model.selected = o }
                }
            }
        }

        if !model.inbox.isEmpty {
            Button {
                model.page = .inbox
            } label: {
                Label("收件箱有 \(model.inbox.count) 条没整理", systemImage: "tray")
            }
            .buttonStyle(.link)
        }

        if !model.journal.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("agent 最近做了").font(.headline)
                ForEach(model.journal.prefix(3), id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.heading).font(.caption.weight(.semibold)).lineLimit(2)
                        ForEach(e.lines.prefix(2), id: \.self) { l in
                            Text(l).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
            }
        }
    }
}
