import SwiftUI
import AppKit
import LifeOSCore

// 出行插件：近期 / 全部 / 想去，加上每次出行的详情页（按天规划，适配一日游和多天多城市）。

struct TravelView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("travelTab") private var tab = TravelTab.upcoming.rawValue

    enum TravelTab: String, CaseIterable, Identifiable {
        case upcoming, all, wishlist
        var id: String { rawValue }
        var label: String {
            switch self { case .upcoming: "近期"; case .all: "全部"; case .wishlist: "想去" }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let id = model.openTripID, let trip = model.trips.first(where: { $0.id == id }) {
                    TripDetailView(trip: trip)
                } else {
                    Text("出行").font(.largeTitle.bold())
                    TabStrip(tabs: TravelTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
                    switch TravelTab(rawValue: tab) ?? .upcoming {
                    case .upcoming: UpcomingTrips()
                    case .all: AllTrips()
                    case .wishlist: WishlistPage()
                    }
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: model.page) {
            if model.page != .travel {
                model.openTripID = nil
                model.tripReturnVisionID = nil
            }
        }
    }
}

// MARK: - 列表

struct UpcomingTrips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let trips = model.trips.filter { $0.dated && !$0.isPast(now: model.clock, calendar: model.calendar) }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if trips.isEmpty {
                Text("最近没有出行计划。").foregroundStyle(.secondary)
            }
            ForEach(trips) { TripCard(trip: $0) }
        }
    }
}

struct AllTrips: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let byYear = Dictionary(grouping: model.trips.filter(\.dated)) { cal.component(.year, from: $0.start) }
        let undated = model.trips.filter { !$0.dated }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if model.trips.isEmpty { Text("还没有出行记录。").foregroundStyle(.secondary) }
            if !undated.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "还没定日期（\(undated.count)）", systemImage: "lightbulb")
                    ForEach(undated) { TripCard(trip: $0, compact: true) }
                }
            }
            ForEach(byYear.keys.sorted(by: >), id: \.self) { year in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "\(year) 年（\(byYear[year]?.count ?? 0) 次）", systemImage: "calendar")
                    ForEach((byYear[year] ?? []).sorted { $0.start > $1.start }) { TripCard(trip: $0, compact: true) }
                }
            }
        }
    }
}

/// 一次出行的卡片
struct TripCard: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    var compact = false

    var body: some View {
        let cal = model.calendar
        let past = trip.isPast(now: model.clock, calendar: cal)
        Button { model.openTrip(trip) } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                CoverImage(url: trip.cover, width: compact ? 56 : 96, height: compact ? 56 : 72)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(trip.title).font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                        StatusPill(text: past ? "去过了" : trip.status)
                    }
                    let route = trip.route.isEmpty ? trip.destination : trip.route
                    if !route.isEmpty { Text(route).foregroundStyle(.secondary).lineLimit(1) }
                    HStack(spacing: 10) {
                        Label(TripFormat.dates(trip, calendar: cal), systemImage: "calendar")
                        if !trip.with.isEmpty { Label(trip.with, systemImage: "person.2") }
                        if !trip.transport.isEmpty { Label(trip.transport, systemImage: "car") }
                    }
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if !past { Text(TripFormat.countdown(trip, now: model.clock, calendar: cal)).font(.callout.weight(.semibold)) }
                    if !trip.packing.isEmpty {
                        Text("要带 \(trip.packing.filter(\.done).count)/\(trip.packing.count)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(compact ? Theme.Space.s : Theme.Space.m)
            .background(.quaternary.opacity(compact ? 0.3 : 0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            .opacity(past ? 0.75 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct WishlistPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            if model.wishlist.isEmpty {
                Text("还没有想去的地方。").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Theme.Space.m)], spacing: Theme.Space.m) {
                ForEach(model.wishlist) { d in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(d.name).font(.headline)
                        if !d.location.isEmpty { Label(d.location, systemImage: "mappin.and.ellipse").foregroundStyle(.secondary) }
                        if !d.why.isEmpty { Text(d.why).font(.callout).lineLimit(3) }
                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                            row("季节", d.season); row("怎么去", d.howToGo); row("几天", d.duration); row("预算", d.budget)
                        }
                        .font(.caption)
                    }
                    .padding(Theme.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ k: String, _ v: String) -> some View {
        if !v.isEmpty {
            GridRow {
                Text(k).foregroundStyle(.secondary)
                Text(v)
            }
        }
    }
}

// MARK: - 详情页

struct TripDetailView: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    @State private var day = 1
    @State private var sharing = false

    var body: some View {
        let cal = model.calendar
        let past = trip.isPast(now: model.clock, calendar: cal)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack {
                Button { model.closeTrip() } label: {
                    Label(model.tripReturnVisionID.flatMap { id in model.vision.visions.first { $0.id == id }?.title } ?? "出行",
                          systemImage: "chevron.left")
                }
                    .buttonStyle(.borderless)
                Spacer()
                if let g = trip.gdocURL {
                    Button { model.openWeb(g) } label: { Label("打开 Google Doc", systemImage: "doc.text") }
                }
                Button { sharing = true } label: { Label("分享", systemImage: "square.and.arrow.up") }
            }
            .sheet(isPresented: $sharing) { ShareTripSheet(trip: trip).environment(model) }

            // 头部
            if trip.cover != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    CoverImage(url: trip.cover, width: nil, height: 180)
                    if !trip.coverCredit.isEmpty {
                        // 网图署名：作者 · 许可（CC BY-SA 要求注明出处）
                        Text("图：" + trip.coverCredit.components(separatedBy: " · ").prefix(2).joined(separator: " · "))
                            .font(.caption2).foregroundStyle(.tertiary)
                            .help(trip.coverCredit)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(trip.title).font(.largeTitle.bold())
                    StatusPill(text: past ? "去过了" : trip.status)
                }
                let route = trip.route.isEmpty ? trip.destination : trip.route
                if !route.isEmpty { Text(route).font(.title3).foregroundStyle(.secondary) }
                HStack(spacing: Theme.Space.l) {
                    Label(TripFormat.dates(trip, calendar: cal), systemImage: "calendar")
                    if !trip.with.isEmpty { Label(trip.with, systemImage: "person.2") }
                    if !trip.transport.isEmpty { Label(trip.transport, systemImage: "car") }
                    if !past { Label(TripFormat.countdown(trip, now: model.clock, calendar: cal), systemImage: "hourglass") }
                }
                .foregroundStyle(.secondary)
                if trip.gdocURL != nil {
                    Label(trip.gdocSynced.map { "已关联 Google Doc · 上次同步 " + Fmt.string($0, "M月d日 H:mm") } ?? "已关联 Google Doc · 还没同步过",
                          systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            // 一眼看到的数字
            let nights = max(0, trip.dayCount(calendar: cal) - 1)
            let est = trip.budget.compactMap(\.estimate).reduce(0, +)
            let act = trip.budget.compactMap(\.actual).reduce(0, +)
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "天数", value: nights == 0 ? "1 天" : "\(nights + 1) 天 \(nights) 晚")
                StatTile(title: "住宿", value: trip.lodging.isEmpty ? (nights == 0 ? "不用" : "还没订") : "\(trip.lodging.count) 处")
                StatTile(title: "预算（预计 / 实际）", value: est == 0 ? "—" : money(est) + (act > 0 ? " / " + money(act) : ""))
                StatTile(title: "要带", value: trip.packing.isEmpty ? "—" : "\(trip.packing.filter(\.done).count) / \(trip.packing.count)")
            }

            // 按天
            if !trip.days.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionTitle(text: "每天", systemImage: "calendar.day.timeline.left")
                    if trip.days.count > 1 {
                        TabStrip(tabs: trip.days.map { d in
                            (String(d.index), "第 \(d.index) 天" + (d.date.map { " " + Fmt.string($0, "M/d") } ?? ""))
                        }, selection: Binding(get: { String(day) }, set: { day = Int($0) ?? 1 }))
                    }
                    if let d = trip.days.first(where: { $0.index == day }) ?? trip.days.first {
                        DayPlan(trip: trip, day: d)
                    }
                }
            }

            TripLodging(trip: trip)
            TripTransport(trip: trip)
            TripTextSection(title: "地点与须知", icon: "mappin.and.ellipse", text: trip.section("地点"))
            TripTextSection(title: "证件与签证", icon: "person.text.rectangle", text: trip.section("证件"))
            TripTextSection(title: "天气", icon: "cloud.sun", text: trip.section("天气"))
            PackingList(trip: trip)
            TripDeadlines(trip: trip)
            TripBudget(trip: trip)
            TripTextSection(title: "记录", icon: "photo.on.rectangle", text: trip.section("记录"))
        }
        .onChange(of: trip.id) { day = 1 }
    }
}

/// 某一天：城市、时间线、当天交通、当晚住宿
struct DayPlan: View {
    @Environment(AppModel.self) private var model
    let trip: Trip
    let day: TripDay

    var body: some View {
        let cal = model.calendar
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 8) {
                Text("第 \(day.index) 天").font(.headline)
                if let d = day.date { Text(Fmt.day(d)).foregroundStyle(.secondary) }
                if !day.city.isEmpty { Label(day.city, systemImage: "building.2").foregroundStyle(.secondary) }
            }
            if day.items.isEmpty {
                Text("这天还没排。").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(day.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.time.isEmpty ? "—" : item.time)
                                .monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.text).fontWeight(.medium)
                                if !item.place.isEmpty { Label(item.place, systemImage: "mappin").font(.callout).foregroundStyle(.secondary) }
                                if !item.note.isEmpty { Text(item.note).font(.callout).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.blue.opacity(0.35)).frame(width: 2).offset(x: 104)
                        }
                    }
                }
            }
            // 当天的交通
            if let t = trip.transportTable, let di = t.header.firstIndex(where: { $0.contains("日期") }), let date = day.date {
                let rows = t.rows.filter { di < $0.count && DateText.parse($0[di], calendar: cal).map { cal.isDate($0, inSameDayAs: date) } == true }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("当天交通", systemImage: "car").font(.callout.weight(.semibold))
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            Text(r.enumerated().filter { $0.offset != di && !$0.element.isEmpty }.map(\.element).joined(separator: " · "))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            // 当晚住哪
            if let date = day.date, let l = trip.lodging.first(where: { l in
                guard let i = l.checkIn else { return false }
                let o = l.checkOut ?? i
                return cal.startOfDay(for: i) <= cal.startOfDay(for: date) && cal.startOfDay(for: date) < cal.startOfDay(for: o)
            }) {
                Label("今晚住：\(l.name)" + (l.address.isEmpty ? "" : "（\(l.address)）"), systemImage: "bed.double")
                    .font(.callout)
            }
        }
        .padding(Theme.Space.l)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

struct TripLodging: View {
    let trip: Trip

    var body: some View {
        if !trip.lodging.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "住宿", systemImage: "bed.double")
                ForEach(trip.lodging) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(l.name).fontWeight(.medium)
                            if !l.city.isEmpty { Text(l.city).foregroundStyle(.secondary) }
                            Spacer()
                            if !l.price.isEmpty { Text(l.price).monospacedDigit() }
                        }
                        Text([l.checkIn.map { "入住 " + Fmt.shortDay($0) }, l.checkOut.map { "退房 " + Fmt.shortDay($0) },
                              l.confirmation.isEmpty ? nil : "确认号 \(l.confirmation)",
                              l.freeCancelUntil.map { "免费取消到 " + Fmt.shortDay($0) }].compactMap { $0 }.joined(separator: " · "))
                            .font(.callout).foregroundStyle(.secondary)
                        if !l.address.isEmpty { Text(l.address).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct TripTransport: View {
    let trip: Trip

    var body: some View {
        if let t = trip.transportTable, !t.rows.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "交通", systemImage: "car")
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow { ForEach(Array(t.header.enumerated()), id: \.offset) { Text($0.element) } }
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(t.rows.enumerated()), id: \.offset) { _, row in
                        GridRow { ForEach(Array(row.enumerated()), id: \.offset) { Text($0.element).textSelection(.enabled) } }
                    }
                }
                .font(.callout)
            }
        }
    }
}

/// 正文小节原样显示（列表、加粗、链接）
struct TripTextSection: View {
    let title: String
    let icon: String
    let text: String

    var body: some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: title, systemImage: icon)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        let t = line.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty {
                            Text(Self.render(t)).font(.callout).textSelection(.enabled)
                                .padding(.leading, line.hasPrefix("  ") ? 16 : 0)
                        }
                    }
                }
            }
        }
    }

    static func render(_ line: String) -> AttributedString {
        var t = line
        if t.hasPrefix("- ") { t = "•  " + t.dropFirst(2) }
        if t.hasPrefix("> ") { t = String(t.dropFirst(2)) }
        return (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }
}

/// 要带：可以在 App 里勾
struct PackingList: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        if !trip.packing.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    SectionTitle(text: "要带", systemImage: "suitcase")
                    Spacer()
                    Text("\(trip.packing.filter(\.done).count) / \(trip.packing.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(trip.packing) { item in
                        Button { model.togglePacking(item, in: trip) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.done ? Theme.green : .secondary)
                                Text(item.text).strikethrough(item.done).foregroundStyle(item.done ? .secondary : .primary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct TripDeadlines: View {
    @Environment(AppModel.self) private var model
    let trip: Trip

    var body: some View {
        if !trip.deadlines.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "出发前要办的（会上日历）", systemImage: "flag")
                ForEach(Array(trip.deadlines.enumerated()), id: \.offset) { _, d in
                    HStack {
                        Text(Fmt.relativeDay(d.date, now: model.clock, calendar: model.calendar))
                            .frame(width: 80, alignment: .leading).monospacedDigit()
                            .foregroundStyle(d.date < model.clock ? .secondary : Theme.orange)
                        Text(d.text)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct TripBudget: View {
    let trip: Trip

    var body: some View {
        if !trip.budget.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "预算", systemImage: "dollarsign.circle")
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { Text("项目"); Text("预计"); Text("实际") }.font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(trip.budget.enumerated()), id: \.offset) { _, b in
                        GridRow {
                            Text(b.item)
                            Text(b.estimate.map(money) ?? "—").monospacedDigit()
                            Text(b.actual.map(money) ?? "—").monospacedDigit()
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        Text("合计").fontWeight(.semibold)
                        Text(money(trip.budget.compactMap(\.estimate).reduce(0, +))).monospacedDigit().fontWeight(.semibold)
                        Text(money(trip.budget.compactMap(\.actual).reduce(0, +))).monospacedDigit().fontWeight(.semibold)
                    }
                }
                .font(.callout)
            }
        }
    }
}

// MARK: - 小部件

struct StatusPill: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.weight(.medium)).tagCapsule(color, horizontal: 7, vertical: 2)
    }
    private var color: Color {
        switch text {
        case "已订好": Theme.green
        case "进行中": Theme.blue
        case "去过了": .secondary
        case "想法": Theme.purple
        default: Theme.orange
        }
    }
}

struct CoverImage: View {
    let url: URL?
    let width: CGFloat?
    let height: CGFloat

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Theme.blue.opacity(0.25), Theme.teal.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "airplane").font(.title2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        // scaledToFill 的图会超出边框；clipShape 只裁掉画面、不裁点击范围，不关掉的话会挡住上面的返回按钮
        .allowsHitTesting(false)
    }
}

/// 右栏：日历上点到出行
struct TripOccurrenceDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let trip: Trip

    var body: some View {
        DetailHeader(occurrence: occurrence)
        VStack(alignment: .leading, spacing: 6) {
            Label(trip.title, systemImage: "airplane")
            if !occurrence.location.isEmpty { Label(occurrence.location, systemImage: "mappin.and.ellipse") }
        }
        .font(.callout)
        HStack {
            Button("打开详情页") { model.openTrip(trip) }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}

enum TripFormat {
    static func dates(_ t: Trip, calendar: Calendar) -> String {
        guard t.dated else { return "日期未定" }
        let n = t.dayCount(calendar: calendar)
        if n <= 1 { return Fmt.day(t.start) }
        return "\(Fmt.shortDay(t.start)) – \(Fmt.shortDay(t.end)) · \(n) 天"
    }

    static func countdown(_ t: Trip, now: Date, calendar: Calendar) -> String {
        guard t.dated else { return "" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: t.start)).day ?? 0
        if days > 1 { return "还有 \(days) 天" }
        if days == 1 { return "明天出发" }
        if days == 0 { return "今天出发" }
        return "进行中"
    }
}
