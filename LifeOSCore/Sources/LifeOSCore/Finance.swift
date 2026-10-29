import Foundation

// 资产与消费：`财务/` 下的流水（按月一个文件）、账户余额、订阅、预算（预留）。
// agent 从用户给的银行截图里读出来写进去，App 只读。不存卡号、账号。

/// 一笔流水
public struct LedgerEntry: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case expense = "支出", income = "收入", transfer = "转账" }

    public var id: String
    public var date: Date
    public var text: String
    public var category: String
    /// 金额（正数）
    public var amount: Double
    public var kind: Kind
    public var account: String
}

/// 一个账户（只记用户起的名字）
public struct Account: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var type: String
    public var balance: Double
    public var updated: Date?
}

/// 一项订阅 / 固定支出
public struct Subscription: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var amount: Double
    public var every: Interval?
    public var everyText: String
    public var next: Date?
    public var account: String
    public var category: String

    /// 每月折算（每年的 ÷ 12，每周的 × 52 / 12）
    public var monthly: Double? {
        guard let e = every else { return nil }
        switch e.unit {
        case .month: return amount / Double(e.value)
        case .year: return amount / Double(12 * e.value)
        case .weekOfYear: return amount * 52 / 12 / Double(e.value)
        case .day: return amount * 365 / 12 / Double(e.value)
        default: return nil
        }
    }

    /// 某段时间里的扣款日：从 next 往前、往后按周期推
    public func charges(in range: DateInterval, calendar: Calendar) -> [Date] {
        guard let next, let every else { return next.map { range.contains($0) ? [$0] : [] } ?? [] }
        var d = next
        var guardCount = 0
        while d > range.start, guardCount < 600, let prev = calendar.date(byAdding: every.unit, value: -every.value, to: d) {
            d = prev; guardCount += 1
        }
        var out: [Date] = []
        guardCount = 0
        while d < range.end, guardCount < 600 {
            if range.contains(d) { out.append(d) }
            guard let n = every.after(d, calendar: calendar) else { break }
            d = n; guardCount += 1
        }
        return out
    }
}

public struct FinanceSnapshot: Equatable, Sendable {
    public var entries: [LedgerEntry]
    public var accounts: [Account]
    public var subscriptions: [Subscription]
    /// 类别 → 每月预算（预留：`财务/预算.md` 有就显示）
    public var budget: [String: Double]

    public static let empty = FinanceSnapshot(entries: [], accounts: [], subscriptions: [], budget: [:])

    public var totalBalance: Double { accounts.map(\.balance).reduce(0, +) }

    public func entries(inMonthOf date: Date, calendar: Calendar) -> [LedgerEntry] {
        entries.filter { calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }

    /// 某月按类别的支出，从多到少
    public func spendingByCategory(inMonthOf date: Date, calendar: Calendar) -> [(category: String, amount: Double)] {
        let month = entries(inMonthOf: date, calendar: calendar).filter { $0.kind == .expense }
        return Dictionary(grouping: month, by: \.category)
            .map { ($0.key, $0.value.map(\.amount).reduce(0, +)) }
            .sorted { $0.1 > $1.1 }
    }

    /// 截至某月的最近 n 个月：每月支出、收入
    /// 某月从 1 号起每天的累计支出；给了 `through` 就只算到那天（本月画到今天为止）
    public func cumulativeSpending(inMonthOf date: Date, through limit: Date? = nil, calendar: Calendar)
        -> [(day: Int, total: Double)] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let byDay = Dictionary(grouping: entries(inMonthOf: date, calendar: calendar).filter { $0.kind == .expense }) {
            calendar.component(.day, from: $0.date)
        }
        let lastDay = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let stop = limit.map { l in l < month.start ? 0 : (l >= month.end ? lastDay : calendar.component(.day, from: l)) } ?? lastDay
        var running = 0.0
        return (1...max(lastDay, 1)).prefix(stop).map { d in
            running += byDay[d]?.map(\.amount).reduce(0, +) ?? 0
            return (d, running)
        }
    }

    /// 预算合计（每月）
    public var totalBudget: Double { budget.values.reduce(0, +) }

    public func monthlyTotals(endingAt date: Date, months n: Int, calendar: Calendar)
        -> [(month: Date, expense: Double, income: Double)] {
        guard let start = calendar.dateInterval(of: .month, for: date)?.start else { return [] }
        return (0..<n).reversed().compactMap { back in
            guard let m = calendar.date(byAdding: .month, value: -back, to: start) else { return nil }
            let es = entries(inMonthOf: m, calendar: calendar)
            return (m, es.filter { $0.kind == .expense }.map(\.amount).reduce(0, +),
                    es.filter { $0.kind == .income }.map(\.amount).reduce(0, +))
        }
    }
}

/// `财务/` 目录
public struct FinanceStore: Sendable {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent("财务") }

    public var ledgerDir: URL { root.appendingPathComponent("流水") }
    public var accountsURL: URL { root.appendingPathComponent("账户.md") }
    public var subscriptionsURL: URL { root.appendingPathComponent("订阅.md") }
    public var budgetURL: URL { root.appendingPathComponent("预算.md") }

    public func load(calendar: Calendar = .current) -> FinanceSnapshot {
        let entries = HealthStore.markdownFiles(in: ledgerDir).flatMap { url -> [LedgerEntry] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return Self.parseLedger(text, fileID: url.lastPathComponent, calendar: calendar)
        }.sorted { $0.date > $1.date }
        func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        return FinanceSnapshot(entries: entries, accounts: Self.parseAccounts(read(accountsURL), calendar: calendar),
                               subscriptions: Self.parseSubscriptions(read(subscriptionsURL), calendar: calendar),
                               budget: Self.parseBudget(read(budgetURL)))
    }

    /// 流水表：| 日期 | 说明 | 类别 | 金额 | 收支 | 账户 |（“收支”列写 支出 / 收入 / 转账；没有这列就按类别猜）
    static func parseLedger(_ text: String, fileID: String, calendar: Calendar) -> [LedgerEntry] {
        let body = Frontmatter.parse(text).body
        guard let t = MarkdownTable.tables(in: body).first(where: { $0.header.contains { $0.contains("金额") } }) else { return [] }
        func col(_ name: String) -> Int? { t.header.firstIndex { $0.contains(name) } }
        guard let di = col("日期"), let ai = col("金额") else { return [] }
        let ti = col("说明") ?? col("商户"), ci = col("类别"), ki = col("收支"), acc = col("账户")
        return t.rows.enumerated().compactMap { i, row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let date = DateText.parse(cell(di), calendar: calendar), let amount = HealthStore.number(cell(ai)) else { return nil }
            let category = cell(ci).isEmpty ? "其他" : cell(ci)
            let kind = LedgerEntry.Kind(rawValue: cell(ki))
                ?? (incomeCategories.contains(category) || cell(ai).trimmingCharacters(in: .whitespaces).hasPrefix("+") ? .income : .expense)
            return LedgerEntry(id: "\(fileID)#\(i)", date: date, text: cell(ti), category: category,
                               amount: abs(amount), kind: kind, account: cell(acc))
        }
    }

    static let incomeCategories: Set<String> = ["生活费", "工资", "收入", "退款", "奖学金", "其他收入"]

    /// 账户表：| 账户 | 类型 | 余额 | 更新日期 |
    static func parseAccounts(_ text: String, calendar: Calendar) -> [Account] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains { $0.contains("余额") } })
        else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        let ni = idx("账户") ?? 0, ti = idx("类型"), bi = idx("余额")!, ui = idx("更新")
        return t.rows.compactMap { row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard !cell(ni).isEmpty, let bal = HealthStore.number(cell(bi)) else { return nil }
            let negative = cell(bi).trimmingCharacters(in: .whitespaces).hasPrefix("-")
            return Account(name: cell(ni), type: cell(ti), balance: negative ? -bal : bal,
                           updated: DateText.parse(cell(ui), calendar: calendar))
        }
    }

    /// 订阅表：| 名称 | 金额 | 周期 | 下次扣款 | 账户 | 类别 |
    static func parseSubscriptions(_ text: String, calendar: Calendar) -> [Subscription] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains { $0.contains("周期") } })
        else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        let ni = idx("名称") ?? 0, ai = idx("金额"), pi = idx("周期"), xi = idx("下次"), acc = idx("账户"), ci = idx("类别")
        return t.rows.compactMap { row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard !cell(ni).isEmpty, let amount = HealthStore.number(cell(ai)) else { return nil }
            return Subscription(name: cell(ni), amount: amount, every: interval(cell(pi)), everyText: cell(pi),
                                next: DateText.parse(cell(xi), calendar: calendar), account: cell(acc),
                                category: cell(ci).isEmpty ? "订阅" : cell(ci))
        }
    }

    /// “每月”“每年”“每周”“3m” 都认
    static func interval(_ s: String) -> Interval? {
        switch s.trimmingCharacters(in: .whitespaces) {
        case "每月", "月付", "monthly": return Interval(value: 1, unit: .month)
        case "每年", "年付", "yearly", "annual": return Interval(value: 1, unit: .year)
        case "每周", "weekly": return Interval(value: 1, unit: .weekOfYear)
        case "每季度", "quarterly": return Interval(value: 3, unit: .month)
        default: return Interval.parse(s.replacingOccurrences(of: "每", with: ""))
        }
    }

    /// 预算表：| 类别 | 每月 |（预留，之后再定）
    static func parseBudget(_ text: String) -> [String: Double] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains { $0.contains("类别") } })
        else { return [:] }
        var out: [String: Double] = [:]
        for row in t.rows where row.count >= 2 {
            if let v = HealthStore.number(row[1]), !row[0].isEmpty { out[row[0]] = v }
        }
        return out
    }
}

public enum FinanceCalendar {
    /// 订阅扣款日 → 日历上的期限
    public static func occurrences(_ subs: [Subscription], fileURL: URL, in range: DateInterval, calendar: Calendar) -> [Occurrence] {
        subs.flatMap { s in
            s.charges(in: range, calendar: calendar).map { d in
                Occurrence(id: "finance:\(s.name)#\(DateText.format(d, withTime: false, calendar: calendar))", style: .deadline,
                           title: "扣款：\(s.name) \(money(s.amount))", subtitle: "订阅", start: calendar.startOfDay(for: d),
                           allDay: true, sourceURL: fileURL, location: s.account)
            }
        }
    }

    public static func money(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v))" : String(format: "$%.2f", v)
    }
}
