import SwiftUI
import AppKit
import LifeOSCore

// 物品插件的界面：找东西 / 资产 / 补货与保养 / 售后 / 搬家，加上每件东西的详情（自行车、汽车有详细保养页）。

/// 物品页
struct ThingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text("物品").font(.largeTitle.bold())
                ThingsPanel()
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// 物品：找东西 / 资产 / 补货与保养 / 售后 / 搬家
struct ThingsPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage("thingsTab") private var tab = ThingsTab.find.rawValue
    @State private var open: Thing?

    enum ThingsTab: String, CaseIterable, Identifiable {
        case find, wishlist, assets, upkeep, aftersales, moving
        var id: String { rawValue }
        var label: String {
            switch self {
            case .find: "找东西"; case .wishlist: "想买"; case .assets: "资产"; case .upkeep: "补货与保养"; case .aftersales: "售后"; case .moving: "搬家"
            }
        }
    }

    var body: some View {
        let current = ThingsTab(rawValue: tab) ?? .find
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            TabStrip(tabs: ThingsTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
            QuickAddField(placeholder: current == .wishlist ? "想买什么？比如“机械键盘”" : "记一件东西：名称，位置（比如“剪刀，厨房第二个抽屉”）",
                          button: current == .wishlist ? "加进想买" : "记下") { text in
                if current == .wishlist { model.addWish(text) } else { model.quickAddThing(text) }
            }
            if current == .wishlist {
                WishlistPanel(open: $open)
            } else if model.things.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("还没有物品。").foregroundStyle(.secondary)
                }
            } else {
                switch current {
                case .find: ThingsFindPage(open: $open)
                case .wishlist: EmptyView()
                case .assets: ThingsAssetsPage(open: $open)
                case .upkeep: ThingsUpkeepPage(open: $open)
                case .aftersales: ThingsAfterSalesPage(open: $open)
                case .moving: ThingsMovingPage(open: $open)
                }
            }
        }
        .sheet(item: $open) { thing in
            ThingDetailSheet(thing: thing)
                .environment(model)
        }
    }
}

// MARK: - 分页

/// 找东西：搜索 + 按位置分组
struct ThingsFindPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?
    @State private var query = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hits = model.things.filter { t in
            q.isEmpty || [t.name, t.location, t.category, t.box, t.serial].contains { $0.lowercased().contains(q) }
        }
        let groups = Dictionary(grouping: hits) { room($0.location) }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            TextField("搜一下：护照、电池、充电器……", text: $query)
                .textFieldStyle(.roundedBorder)
            if hits.isEmpty {
                Text("没找到。").foregroundStyle(.secondary)
            }
            ForEach(groups.keys.sorted(), id: \.self) { room in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: room, systemImage: "mappin.and.ellipse")
                    ForEach(groups[room] ?? []) { t in
                        ThingRow(thing: t, detail: t.location.isEmpty ? "没写位置" : t.location) { open = t }
                    }
                }
            }
        }
    }

    /// 位置的第一段当作房间：“卧室 · 书桌左抽屉” → “卧室”
    private func room(_ location: String) -> String {
        let first = location.components(separatedBy: CharacterSet(charactersIn: "·/>，,")).first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? "没写位置" : first
    }
}

/// 资产：总价值 + 按类别
struct ThingsAssetsPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?

    var body: some View {
        let owned = model.things.filter { $0.status != "已卖" && $0.status != "丢了" && !$0.isConsumable }
        let groups = Dictionary(grouping: owned, by: \.category)
        let total = owned.compactMap(\.price).reduce(0, +)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "总价值（买入价）", value: money(total))
                StatTile(title: "物品", value: "\(owned.count) 件")
                StatTile(title: "借出", value: "\(owned.filter { $0.status == "借出" }.count) 件")
            }
            ForEach(groups.keys.sorted(), id: \.self) { cat in
                let items = (groups[cat] ?? []).sorted { ($0.price ?? 0) > ($1.price ?? 0) }
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack {
                        SectionTitle(text: cat, systemImage: "square.grid.2x2")
                        Spacer()
                        Text(money(items.compactMap(\.price).reduce(0, +))).foregroundStyle(.secondary).monospacedDigit()
                    }
                    ForEach(items) { t in
                        ThingRow(thing: t, detail: [t.price.map(money), t.purchased.map { "买于 " + Fmt.shortDay($0) },
                                                    t.status == "借出" ? "借给 \(t.lentTo)" : nil]
                                    .compactMap { $0 }.joined(separator: " · ")) { open = t }
                    }
                }
            }
        }
    }
}

/// 补货与保养：按日期排
struct ThingsUpkeepPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?

    private struct Due: Identifiable {
        var id: String
        var thing: Thing
        var what: String
        var date: Date?
        var note: String
    }

    var body: some View {
        let cal = model.calendar
        let restock = model.things.filter(\.isConsumable).map {
            Due(id: $0.id + "#r", thing: $0, what: "补货", date: $0.nextRestock(calendar: cal),
                note: [$0.lasts.map { "一份用 \($0.text)" }, $0.restocked.map { "上次 " + Fmt.shortDay($0) }].compactMap { $0 }.joined(separator: " · "))
        }
        let upkeep = model.things.flatMap { t in
            t.maintenanceTasks(calendar: cal).map { task in
                Due(id: t.id + "#" + task.name, thing: t, what: task.name == "保养" ? "保养" : task.name, date: task.next,
                    note: [task.everyText.isEmpty ? nil : task.everyText, task.last.map { "上次 " + Fmt.shortDay($0) }]
                        .compactMap { $0 }.joined(separator: " · "))
            }
        }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            dueList("补货", "cart", restock.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) })
            dueList("保养", "wrench.and.screwdriver", upkeep.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) })
        }
    }

    @ViewBuilder
    private func dueList(_ title: String, _ icon: String, _ items: [Due]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: title, systemImage: icon)
            if items.isEmpty {
                Text(title == "补货" ? "没有耗材（物品卡写上 lasts 和 restocked 就会出现在这里）。" : "没有要保养的东西。")
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { d in
                Button { open = d.thing } label: {
                    HStack(spacing: 10) {
                        Text(d.date.map { Fmt.relativeDay($0, now: model.clock, calendar: model.calendar) } ?? "—")
                            .frame(width: 70, alignment: .leading).monospacedDigit()
                            .foregroundStyle(soon(d.date) ? Theme.orange : .secondary)
                        Text(d.thing.name).fontWeight(.medium)
                        if d.what != "补货" && d.what != "保养" { Text(d.what) }
                        Spacer()
                        Text(d.note).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
            }
        }
    }

    private func soon(_ d: Date?) -> Bool {
        guard let d else { return false }
        return d.timeIntervalSince(model.clock) < Double(ThingCalendar.leadDays) * 86400
    }
}

/// 售后：退货、保修、序列号
struct ThingsAfterSalesPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?

    var body: some View {
        let now = model.clock
        let returns = model.things.filter { ($0.returnUntil ?? .distantPast) >= now }.sorted { $0.returnUntil! < $1.returnUntil! }
        let warranty = model.things.filter { $0.warrantyUntil != nil }.sorted { $0.warrantyUntil! < $1.warrantyUntil! }
        let serials = model.things.filter { !$0.serial.isEmpty }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            section("还能退货", "arrow.uturn.backward", returns.map { ($0, "截止 " + Fmt.day($0.returnUntil!)) }, empty: "没有在退货期内的东西。")
            section("保修", "checkmark.shield", warranty.map { t in
                (t, (t.warrantyUntil! < now ? "已过保 " : "保修到 ") + Fmt.day(t.warrantyUntil!))
            }, empty: "还没记保修期。")
            section("序列号", "number", serials.map { ($0, $0.serial) }, empty: "还没记序列号。")
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ icon: String, _ rows: [(Thing, String)], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: title, systemImage: icon)
            if rows.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(rows, id: \.0.id) { t, detail in ThingRow(thing: t, detail: detail) { open = t } }
        }
    }
}

/// 搬家：按箱子分组
struct ThingsMovingPage: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?

    var body: some View {
        let groups = Dictionary(grouping: model.things.filter { $0.status != "已卖" }) { $0.box.isEmpty ? "还没装箱" : $0.box }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("搬家时用：让 agent 给每件东西写上 box（装在哪个箱子），这里按箱子列出来。")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(groups.keys.sorted { a, b in a == "还没装箱" ? false : b == "还没装箱" ? true : a < b }, id: \.self) { box in
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "\(box)（\(groups[box]?.count ?? 0)）", systemImage: "shippingbox")
                    ForEach(groups[box] ?? []) { t in ThingRow(thing: t, detail: t.location) { open = t } }
                }
            }
        }
    }
}

// MARK: - 行与详情

/// 一件东西：缩略图 + 名字 + 一行说明
struct ThingRow: View {
    let thing: Thing
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ThingThumb(url: thing.photo, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(thing.name).fontWeight(.medium)
                        if thing.detailed {
                            Image(systemName: "wrench.and.screwdriver").font(.caption).foregroundStyle(.secondary)
                        }
                        if thing.status != "在用" {
                            Text(thing.status).font(.caption).tagCapsule(.secondary, horizontal: 6, vertical: 1)
                        }
                    }
                    if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

struct ThingThumb: View {
    let url: URL?
    var size: CGFloat

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "shippingbox").foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
        .allowsHitTesting(false)  // 同 CoverImage：超出边框的部分别挡住相邻的行
    }
}

/// 一件东西的详情；有详细保养页的（自行车、汽车）多出规格、保养计划、保养记录
struct ThingDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let thing: Thing

    var body: some View {
        let cal = model.calendar
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(thing.name).font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Theme.Space.l)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack(alignment: .top, spacing: Theme.Space.l) {
                        if thing.photo != nil { ThingThumb(url: thing.photo, size: 160) }
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            field("类别", thing.category)
                            field("位置", thing.location)
                            field("状态", thing.status == "借出" ? "借出（\(thing.lentTo)）" : thing.status)
                            field("价格", thing.price.map(money) ?? "")
                            field("购买", [thing.purchased.map(Fmt.day), thing.store.isEmpty ? nil : thing.store].compactMap { $0 }.joined(separator: " · "))
                            field("退货截止", thing.returnUntil.map(Fmt.day) ?? "")
                            field("保修到", thing.warrantyUntil.map(Fmt.day) ?? "")
                            field("序列号", thing.serial)
                            field("箱子", thing.box)
                            if let next = thing.nextRestock(calendar: cal) { field("下次补货", Fmt.day(next)) }
                        }
                        .font(.callout)
                    }

                    if !thing.specs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: "规格", systemImage: "list.bullet.rectangle")
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                                ForEach(Array(thing.specs.enumerated()), id: \.offset) { _, row in
                                    GridRow {
                                        Text(row.first ?? "").foregroundStyle(.secondary)
                                        Text(row.dropFirst().filter { !$0.isEmpty }.joined(separator: " · "))
                                    }
                                }
                            }
                            .font(.callout)
                        }
                    }

                    let tasks = thing.maintenanceTasks(calendar: cal)
                    if !tasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionTitle(text: "保养计划", systemImage: "wrench.and.screwdriver")
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                                GridRow { Text("项目"); Text("间隔"); Text("上次"); Text("下次") }
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(tasks) { t in
                                    GridRow {
                                        Text(t.name)
                                        Text(t.everyText).foregroundStyle(.secondary)
                                        Text(t.last.map(Fmt.shortDay) ?? "—").monospacedDigit()
                                        Text(t.next.map { Fmt.relativeDay($0, now: model.clock, calendar: cal) } ?? (t.note.isEmpty ? "—" : t.note))
                                            .foregroundStyle((t.next ?? .distantFuture) < model.clock ? Theme.orange : .primary)
                                    }
                                }
                            }
                            .font(.callout)
                        }
                    }

                    let log = thing.maintenanceLog(calendar: cal)
                    if !log.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                SectionTitle(text: "保养记录", systemImage: "clock.arrow.circlepath")
                                Spacer()
                                Text("累计花费 " + money(log.compactMap(\.cost).reduce(0, +)))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                                GridRow { Text("日期"); Text("做了什么"); Text("里程"); Text("花费"); Text("在哪") }
                                    .font(.caption).foregroundStyle(.secondary)
                                ForEach(log) { e in
                                    GridRow {
                                        Text(e.date.map(Fmt.shortDay) ?? e.dateText).monospacedDigit()
                                        Text(e.what)
                                        Text(e.mileage).foregroundStyle(.secondary)
                                        Text(e.cost.map(money) ?? "").monospacedDigit()
                                        Text(e.place).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .font(.callout)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 620, height: 560)
    }

    @ViewBuilder
    private func field(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            GridRow {
                Text(label).foregroundStyle(.secondary)
                Text(value).textSelection(.enabled)
            }
        }
    }
}

/// 右栏：日历上点到一条物品提醒
struct ThingOccurrenceDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence
    let thing: Thing

    var body: some View {
        DetailHeader(occurrence: occurrence)
        VStack(alignment: .leading, spacing: 6) {
            if !thing.location.isEmpty { Label(thing.location, systemImage: "mappin.and.ellipse") }
            if let p = thing.price { Label(money(p), systemImage: "dollarsign.circle") }
        }
        .font(.callout)
        HStack {
            Button("打开物品页") { model.page = .things }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}

/// 分页条：一排胶囊按钮（五个分页时原生分段控件会在窄栏里触发 AppKit 约束死循环，所以自己画）
struct TabStrip: View {
    let tabs: [(id: String, label: String)]
    @Binding var selection: String
    /// 大号：健康三页顶上的 日 / 周 / 月
    var large = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.id) { tab in
                let on = tab.id == selection
                Button { selection = tab.id } label: {
                    Text(tab.label)
                        .font((large ? Font.title3 : .callout).weight(on ? .semibold : .regular))
                        .padding(.horizontal, large ? 20 : 12).padding(.vertical, large ? 8 : 5)
                        .background(on ? Color.accentColor.opacity(0.18) : .clear, in: Capsule())
                        .foregroundStyle(on ? Color.accentColor : .primary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

/// 金额（默认美元）
func money(_ v: Double) -> String {
    v == v.rounded() ? "$\(Int(v))" : String(format: "$%.2f", v)
}


/// 一行输入框 + 按钮
struct QuickAddField: View {
    let placeholder: String
    let button: String
    let submit: (String) -> Void
    @State private var draft = ""

    var body: some View {
        HStack {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            Button(button, action: save)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func save() {
        let t = draft.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        submit(t)
        draft = ""
    }
}

/// 想买：每一项旁边列出已有的类似东西
struct WishlistPanel: View {
    @Environment(AppModel.self) private var model
    @Binding var open: Thing?

    var body: some View {
        let open_ = model.thingWishes.filter(\.isOpen)
        let done = model.thingWishes.filter { !$0.isOpen }
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if model.thingWishes.isEmpty {
                Text("想买什么先记在这里。agent 会先查你已经有没有一样或类似的东西，再一起决定买不买。").foregroundStyle(.secondary)
            }
            ForEach(open_) { w in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(w.name).font(.headline)
                        if !w.price.isEmpty { Text(w.price).foregroundStyle(.secondary) }
                        Spacer()
                        if let d = w.added { Text("加入于 " + Fmt.shortDay(d)).font(.caption).foregroundStyle(.secondary) }
                    }
                    if !w.why.isEmpty { Text(w.why).font(.callout) }
                    let similar = ThingMatch.similar(to: w.name, in: model.things)
                    if similar.isEmpty {
                        Label("物品里没找到类似的", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                    } else {
                        Label("已经有类似的：", systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(Theme.orange)
                        ForEach(similar) { t in
                            ThingRow(thing: t, detail: [t.location, t.status].filter { !$0.isEmpty }.joined(separator: " · ")) { open = t }
                                .padding(.leading, 20)
                        }
                    }
                }
                .padding(Theme.Space.m)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SectionTitle(text: "已经决定的", systemImage: "archivebox")
                    ForEach(done) { w in
                        HStack {
                            Text(w.name)
                            Text(w.result).font(.caption).tagCapsule(w.result == "买了" ? Theme.green : .secondary, horizontal: 6, vertical: 1)
                            if !w.note.isEmpty { Text(w.note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}
