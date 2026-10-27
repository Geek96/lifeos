import SwiftUI
import Charts
import LifeOSCore

// 消费：概览 / 流水 / 账户 / 订阅。只陈述数字，不评价、不催。

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
            HStack(spacing: Theme.Space.m) {
                StatTile(title: "\(Fmt.string(now, "M月"))支出", value: money(spent))
                StatTile(title: "\(Fmt.string(now, "M月"))收入", value: money(earned))
                StatTile(title: "结余", value: money(earned - spent))
                StatTile(title: "账户合计", value: f.accounts.isEmpty ? "—" : money(f.totalBalance))
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "这个月花在哪", systemImage: "chart.bar.xaxis")
                if cats.isEmpty {
                    FinanceEmptyHint(text: "这个月还没有流水。把银行的消费截图发给 agent，它会读出来写进 财务/流水/。")
                } else {
                    CategoryBars(cats: cats, budget: f.budget)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.s) {
                SectionTitle(text: "预算", systemImage: "target")
                if f.budget.isEmpty {
                    FinanceEmptyHint(text: "还没定预算（之后再讨论）。定好后写进 财务/预算.md，这里会显示每个类别用了多少、还剩多少。")
                } else {
                    Text("上面每个类别的竖线就是预算。").font(.callout).foregroundStyle(.secondary)
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

/// 按类别的横条，有预算时画一条竖线
struct CategoryBars: View {
    let cats: [(category: String, amount: Double)]
    let budget: [String: Double]

    var body: some View {
        Chart {
            ForEach(cats, id: \.category) { c in
                BarMark(x: .value("金额", c.amount), y: .value("类别", c.category))
                    .foregroundStyle(Theme.orange.gradient)
                    .annotation(position: .trailing) { Text(money(c.amount)).font(.caption).foregroundStyle(.secondary) }
                if let b = budget[c.category] {
                    RuleMark(xStart: .value("预算", b), xEnd: .value("预算", b), y: .value("类别", c.category))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(.secondary)
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
