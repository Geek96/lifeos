import SwiftUI
import Charts
import LifeOSCore

// 消费：概览（类别圆环、本月累计对照上月、预算进度）/ 流水 / 账户 / 订阅。只陈述数字，不评价、不催。

struct FinanceView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("financeTab") private var tab = FinanceTab.overview.rawValue

    enum FinanceTab: String, CaseIterable, Identifiable {
        case overview, ledger, accounts, subscriptions
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "概览"; case .ledger: "流水"; case .accounts: "账户"; case .subscriptions: "订阅"
            }
        }
    }

    var body: some View {
        let current = FinanceTab(rawValue: tab) ?? .overview
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text("消费").font(.largeTitle.bold())
                TabStrip(tabs: FinanceTab.allCases.map { ($0.rawValue, $0.label) }, selection: $tab)
                switch current {
                case .overview: FinanceOverview()
                case .ledger: LedgerPage()
                case .accounts: AccountsPage()
                case .subscriptions: SubscriptionsPage()
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// 数据还没有时的提示
struct FinanceEmptyHint: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary)
    }
}

/// 概览：本月收支、账户总额、按类别、最近几笔、接下来的扣款；预算位置预留
struct FinanceOverview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let f = model.finance
        let now = model.clock
        let month = f.entries(inMonthOf: now, calendar: cal)
        let spent = month.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
        let earned = month.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
        let cats = f.spendingByCategory(inMonthOf: now, calendar: cal)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            StatRow {
                StatTile(title: "\(Fmt.string(now, "M月"))支出", value: money(spent))
                StatTile(title: "\(Fmt.string(now, "M月"))收入", value: money(earned))
                StatTile(title: "结余", value: money(earned - spent))
                StatTile(title: "账户合计", value: f.accounts.isEmpty ? "—" : money(f.totalBalance))
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "这个月花在哪", systemImage: "chart.pie")
                if cats.isEmpty {
                    FinanceEmptyHint(text: "这个月还没有流水。把银行的消费截图发给 agent，它会读出来写进 财务/流水/。")
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: Theme.Space.xl) {
                            CategoryDonut(cats: cats, total: spent).frame(width: 180, height: 180)
                            CategoryBars(cats: cats, budget: f.budget)
                        }
                        VStack(alignment: .leading, spacing: Theme.Space.l) {
                            CategoryDonut(cats: cats, total: spent).frame(width: 180, height: 180)
                            CategoryBars(cats: cats, budget: f.budget)
                        }
                    }
                }
            }

            CumulativeSpendingChart()

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "预算", systemImage: "target")
                if f.budget.isEmpty {
                    FinanceEmptyHint(text: "还没定预算（之后再讨论）。定好后写进 财务/预算.md，这里会显示每个类别用了多少、还剩多少，累计图上也会画一条预算线。")
                } else {
                    BudgetProgress(month: now)
                }
            }

            let upcoming = f.subscriptions.compactMap { s -> (Subscription, Date)? in
                s.charges(in: DateInterval(start: cal.startOfDay(for: now), duration: 14 * 86400), calendar: cal).first.map { (s, $0) }
            }.sorted { $0.1 < $1.1 }
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "接下来两周扣款", systemImage: "calendar.badge.clock")
                    ForEach(upcoming, id: \.0.id) { s, d in
                        HStack {
                            Text(Fmt.relativeDay(d, now: now, calendar: cal)).frame(width: 70, alignment: .leading).foregroundStyle(.secondary)
                            Text(s.name)
                            Spacer()
                            Text(money(s.amount)).monospacedDigit()
                        }
                    }
                }
            }

            if !f.entries.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "最近几笔", systemImage: "list.bullet")
                    ForEach(f.entries.prefix(8)) { e in LedgerRow(entry: e) }
                }
            }
        }
    }
}

/// 类别的颜色：按名字排好序后在色环上取，同一个类别在各张图里颜色一样
enum CategoryColor {
    static let palette: [Color] = [Theme.orange, Theme.blue, Theme.green, Theme.purple, Theme.teal, Theme.indigo, Theme.red]

    static func color(_ category: String, among all: [String]) -> Color {
        let i = all.sorted().firstIndex(of: category) ?? 0
        return palette[i % palette.count]
    }
}

/// 这个月各类别占多少（圆环，中间写合计）
struct CategoryDonut: View {
    let cats: [(category: String, amount: Double)]
    let total: Double

    var body: some View {
        let names = cats.map(\.category)
        Chart(cats, id: \.category) { c in
            SectorMark(angle: .value("金额", c.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                .foregroundStyle(CategoryColor.color(c.category, among: names))
                .cornerRadius(3)
        }
        .chartLegend(.hidden)
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text("合计").font(.caption).foregroundStyle(.secondary)
                Text(money(total)).font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
        .accessibilityLabel(cats.map { "\($0.category) \(money($0.amount))" }.joined(separator: "，"))
    }
}

/// 本月从 1 号起的累计支出（实线，画到今天）对照上个月（灰虚线）；有预算时画预算线
struct CumulativeSpendingChart: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let f = model.finance
        let now = model.clock
        let this = f.cumulativeSpending(inMonthOf: now, through: now, calendar: cal)
        let last = cal.date(byAdding: .month, value: -1, to: now).map { f.cumulativeSpending(inMonthOf: $0, calendar: cal) } ?? []
        let budget = f.totalBudget
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "这个月累计花了多少", systemImage: "chart.line.uptrend.xyaxis")
            if (this.last?.total ?? 0) == 0 && (last.last?.total ?? 0) == 0 {
                FinanceEmptyHint(text: "这个月和上个月都还没有支出记录。")
            } else {
                Chart {
                    ForEach(last, id: \.day) { p in
                        LineMark(x: .value("日", p.day), y: .value("累计", p.total), series: .value("月", "上个月"))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.stepEnd)
                    }
                    ForEach(this, id: \.day) { p in
                        LineMark(x: .value("日", p.day), y: .value("累计", p.total), series: .value("月", "这个月"))
                            .foregroundStyle(Theme.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.stepEnd)
                    }
                    if let p = this.last {
                        PointMark(x: .value("日", p.day), y: .value("累计", p.total))
                            .foregroundStyle(Theme.orange)
                            .annotation(position: .top, alignment: .trailing) {
                                Text(money(p.total)).font(.caption.weight(.semibold)).foregroundStyle(Theme.orange)
                            }
                    }
                    if budget > 0 {
                        RuleMark(y: .value("预算", budget))
                            .foregroundStyle(DailyBarChart.goalColor)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("预算 \(money(budget))").font(.caption2.weight(.semibold)).foregroundStyle(DailyBarChart.goalColor)
                            }
                    }
                }
                .chartXScale(domain: 1...31)
                .chartXAxis { AxisMarks(values: [1, 5, 10, 15, 20, 25, 31]) { v in AxisValueLabel { if let d = v.as(Int.self) { Text("\(d) 日") } } } }
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self) { Text(money(n)) } } } }
                .frame(height: 170)
                Text("橙线 = 这个月（到今天）；灰虚线 = 上个月同一天累计到多少。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 每个类别用了预算的几成；超了变红。最上面一条是合计
struct BudgetProgress: View {
    @Environment(AppModel.self) private var model
    let month: Date

    var body: some View {
        let f = model.finance
        let spent = Dictionary(uniqueKeysWithValues: f.spendingByCategory(inMonthOf: month, calendar: model.calendar).map { ($0.category, $0.amount) })
        let rows = f.budget.sorted { $0.value > $1.value }
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            bar("合计", used: rows.map { spent[$0.key] ?? 0 }.reduce(0, +), of: f.totalBudget, bold: true)
            ForEach(rows, id: \.key) { cat, b in
                bar(cat, used: spent[cat] ?? 0, of: b, bold: false)
            }
            Text("只算预算里写了的类别。").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bar(_ name: String, used: Double, of budget: Double, bold: Bool) -> some View {
        let p = budget > 0 ? used / budget : 0
        let color = p > 1 ? Theme.red : (p > 0.8 ? Theme.orange : Theme.teal)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).fontWeight(bold ? .semibold : .medium)
                Spacer()
                Text("\(money(used)) / \(money(budget))").monospacedDigit().foregroundStyle(p > 1 ? Theme.red : .secondary)
                Text(p > 1 ? "超了 \(money(used - budget))" : "还剩 \(money(budget - used))")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule().fill(color).frame(width: g.size.width * min(p, 1))
                }
            }
            .frame(height: bold ? 10 : 7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) 用了 \(money(used))，预算 \(money(budget))")
    }
}

/// 按类别的横条，有预算时画一条竖线
struct CategoryBars: View {
    let cats: [(category: String, amount: Double)]
    let budget: [String: Double]

    var body: some View {
        let names = cats.map(\.category)
        Chart {
            ForEach(cats, id: \.category) { c in
                BarMark(x: .value("金额", c.amount), y: .value("类别", c.category))
                    .foregroundStyle(CategoryColor.color(c.category, among: names).gradient)
                    .annotation(position: .trailing) { Text(money(c.amount)).font(.caption).foregroundStyle(.secondary) }
                if let b = budget[c.category] {
                    RuleMark(xStart: .value("预算", b), xEnd: .value("预算", b), y: .value("类别", c.category))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(DailyBarChart.goalColor)
                }
            }
        }
        .frame(height: CGFloat(max(cats.count, 2)) * 30)
    }
}

struct LedgerRow: View {
    @Environment(AppModel.self) private var model
    let entry: LedgerEntry

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.string(entry.date, "M/d")).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Text(entry.text.isEmpty ? entry.category : entry.text).lineLimit(1)
            Text(entry.category).font(.caption).tagCapsule(.secondary, horizontal: 6, vertical: 1)
            Spacer()
            if !entry.account.isEmpty { Text(entry.account).font(.caption).foregroundStyle(.secondary) }
            Text((entry.kind == .income ? "+" : entry.kind == .expense ? "−" : "") + money(entry.amount))
                .monospacedDigit()
                .foregroundStyle(entry.kind == .income ? Theme.green : .primary)
                .frame(minWidth: 80, alignment: .trailing)
        }
        .font(.callout)
    }
}

/// 流水：按月翻，每月合计和按类别，近 12 个月趋势
struct LedgerPage: View {
    @Environment(AppModel.self) private var model
    @State private var month = Date()

    var body: some View {
        let cal = model.calendar
        let f = model.finance
        let entries = f.entries(inMonthOf: month, calendar: cal)
        let spent = entries.filter { $0.kind == .expense }.map(\.amount).reduce(0, +)
        let earned = entries.filter { $0.kind == .income }.map(\.amount).reduce(0, +)
        let trend = f.monthlyTotals(endingAt: model.clock, months: 12, calendar: cal)
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if f.entries.isEmpty {
                FinanceEmptyHint(text: "还没有流水。把银行或信用卡的消费截图发给 agent，它会按月写进 财务/流水/YYYY-MM.md。")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("近 12 个月（橙 = 支出，绿 = 收入）").font(.caption).foregroundStyle(.secondary)
                    Chart {
                        ForEach(trend, id: \.month) { m in
                            BarMark(x: .value("月", m.month, unit: .month), y: .value("支出", m.expense))
                                .foregroundStyle(Theme.orange)
                                .position(by: .value("收支", "支出"))
                            BarMark(x: .value("月", m.month, unit: .month), y: .value("收入", m.income))
                                .foregroundStyle(Theme.green)
                                .position(by: .value("收支", "收入"))
                        }
                    }
                    .frame(height: 160)
                }

                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                    Text(Fmt.string(month, "yyyy年M月")).font(.title3.weight(.semibold))
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                    Spacer()
                    Text("支出 \(money(spent)) · 收入 \(money(earned))").foregroundStyle(.secondary).monospacedDigit()
                }

                let cats = f.spendingByCategory(inMonthOf: month, calendar: cal)
                if !cats.isEmpty { CategoryBars(cats: cats, budget: f.budget) }

                if entries.isEmpty {
                    Text("这个月没有记录。").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { e in LedgerRow(entry: e) }
                    }
                }
            }
        }
    }

    private func shift(_ n: Int) {
        month = model.calendar.date(byAdding: .month, value: n, to: month) ?? month
    }
}

/// 账户：余额与更新日期
struct AccountsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.finance
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if f.accounts.isEmpty {
                FinanceEmptyHint(text: "还没有账户。把余额截图发给 agent，它只记你给账户起的名字和余额（不记卡号、账号），写进 财务/账户.md。")
            } else {
                StatTile(title: "合计", value: money(f.totalBalance))
                ForEach(f.accounts) { a in
                    HStack {
                        Image(systemName: a.balance < 0 ? "creditcard" : "building.columns").foregroundStyle(.secondary).frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).fontWeight(.medium)
                            Text([a.type, a.updated.map { "更新于 " + Fmt.shortDay($0) }].compactMap { $0 }.filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(a.balance)).monospacedDigit().foregroundStyle(a.balance < 0 ? Theme.red : .primary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

/// 订阅与固定支出
struct SubscriptionsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let subs = model.finance.subscriptions.sorted { ($0.next ?? .distantFuture) < ($1.next ?? .distantFuture) }
        let monthly = subs.compactMap(\.monthly).reduce(0, +)
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if subs.isEmpty {
                FinanceEmptyHint(text: "还没有订阅。房租、手机费、软件订阅这类固定扣款，跟 agent 说一声，它会写进 财务/订阅.md，扣款日会上日历。")
            } else {
                HStack(spacing: Theme.Space.m) {
                    StatTile(title: "每月固定支出（折算）", value: money(monthly))
                    StatTile(title: "每年合计", value: money(monthly * 12))
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("名称"); Text("金额"); Text("周期"); Text("下次扣款"); Text("账户") }
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(subs) { s in
                        GridRow {
                            Text(s.name).fontWeight(.medium)
                            Text(money(s.amount)).monospacedDigit()
                            Text(s.everyText).foregroundStyle(.secondary)
                            Text(s.next.map { Fmt.relativeDay($0, now: model.clock, calendar: model.calendar) } ?? "—")
                            Text(s.account).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
            }
        }
    }
}

/// 右栏：日历上点到一次订阅扣款
struct FinanceOccurrenceDetail: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence

    var body: some View {
        DetailHeader(occurrence: occurrence)
        if !occurrence.location.isEmpty {
            Label(occurrence.location, systemImage: "creditcard").font(.callout)
        }
        HStack {
            Button("打开消费") { model.page = .finance }
        }
        .buttonStyle(.link)
        .font(.callout)
    }
}
