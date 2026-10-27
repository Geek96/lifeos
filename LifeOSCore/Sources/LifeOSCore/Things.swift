import Foundation

// 物品插件：`物品/` 下每件东西一张卡（frontmatter 平铺），agent 写、App 只读。
// 只有“过了会吃亏”的（退货截止、保修到期）上日历当期限；补货、保养是时间窗，不催。

/// 间隔：“14d”“2w”“3m”“1y”“45天”“2周”“3个月”“1年”
public struct Interval: Equatable, Sendable {
    public var value: Int
    public var unit: Calendar.Component

    public static func parse(_ s: String) -> Interval? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        guard let r = t.range(of: #"^\d+"#, options: .regularExpression), let n = Int(t[r]), n > 0 else { return nil }
        let rest = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        switch rest {
        case "d", "day", "days", "天", "日": return Interval(value: n, unit: .day)
        case "w", "wk", "week", "weeks", "周", "星期": return Interval(value: n, unit: .weekOfYear)
        case "m", "mo", "month", "months", "个月", "月": return Interval(value: n, unit: .month)
        case "y", "yr", "year", "years", "年": return Interval(value: n, unit: .year)
        default: return nil
        }
    }

    public func after(_ date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: unit, value: value, to: date)
    }

    public var text: String {
        switch unit {
        case .day: return "\(value) 天"
        case .weekOfYear: return "\(value) 周"
        case .month: return "\(value) 个月"
        case .year: return "\(value) 年"
        default: return "\(value)"
        }
    }
}

/// 详细保养页里的一项计划：多久做一次、上次什么时候
public struct MaintenanceTask: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var every: Interval?
    /// 间隔原文（可能是“每 500 km”这种 App 不会算的）
    public var everyText: String
    public var last: Date?
    public var note: String
    public var next: Date?
}

/// 一条保养记录
public struct MaintenanceLog: Equatable, Sendable, Identifiable {
    public var id: Int
    public var date: Date?
    public var dateText: String
    public var what: String
    public var mileage: String
    public var cost: Double?
    public var place: String
}

public struct Thing: Equatable, Sendable, Identifiable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var name: String
    public var category: String
    public var location: String
    public var box: String
    /// 在用 / 借出 / 闲置 / 已卖 …
    public var status: String
    public var lentTo: String
    public var price: Double?
    public var currency: String
    public var purchased: Date?
    public var store: String
    public var warrantyUntil: Date?
    public var returnUntil: Date?
    public var serial: String
    /// 耗材：一份大概用多久、上次买的日期
    public var lasts: Interval?
    public var restocked: Date?
    /// 简单保养：多久一次、上次
    public var maintainEvery: Interval?
    public var maintained: Date?
    public var photo: URL?
    /// 有详细保养页（自行车、汽车）
    public var detailed: Bool
    public var body: String

    public var isConsumable: Bool { lasts != nil }

    public func nextRestock(calendar: Calendar) -> Date? {
        guard let lasts, let restocked else { return nil }
        return lasts.after(restocked, calendar: calendar)
    }

    /// 所有保养项：简单的一项 + 详细页“保养计划”表里的每一项
    public func maintenanceTasks(calendar: Calendar) -> [MaintenanceTask] {
        var tasks: [MaintenanceTask] = []
        if let maintainEvery {
            tasks.append(MaintenanceTask(name: "保养", every: maintainEvery, everyText: maintainEvery.text, last: maintained,
                                         note: "", next: maintained.flatMap { maintainEvery.after($0, calendar: calendar) }))
        }
        if let table = section("保养计划") {
            for row in table.rows {
                let c = row + Array(repeating: "", count: max(0, 4 - row.count))
                guard !c[0].isEmpty else { continue }
                let every = Interval.parse(c[1].replacingOccurrences(of: "每", with: ""))
                let last = DateText.parse(c[2], calendar: calendar)
                tasks.append(MaintenanceTask(name: c[0], every: every, everyText: c[1], last: last, note: c[3],
                                             next: every.flatMap { e in last.flatMap { e.after($0, calendar: calendar) } }))
            }
        }
        return tasks
    }

    /// 详细页“保养记录”表，新的在前
    public func maintenanceLog(calendar: Calendar) -> [MaintenanceLog] {
        guard let table = section("保养记录") else { return [] }
        return table.rows.enumerated().compactMap { i, row in
            let c = row + Array(repeating: "", count: max(0, 5 - row.count))
            guard !(c[0].isEmpty && c[1].isEmpty) else { return nil }
            return MaintenanceLog(id: i, date: DateText.parse(c[0], calendar: calendar), dateText: c[0], what: c[1],
                                  mileage: c[2], cost: HealthStore.number(c[3]), place: c[4])
        }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    /// 详细页“规格”表（部件 | 型号 / 尺寸）
    public var specs: [[String]] { section("规格")?.rows ?? [] }

    /// 正文里标题含 `name` 的 `## ` 小节的第一张表
    func section(_ name: String) -> MarkdownTable.Table? {
        var inSection = false
        var lines: [String] = []
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = line.contains(name)
                continue
            }
            if inSection { lines.append(line) }
        }
        return MarkdownTable.tables(in: lines.joined(separator: "\n")).first
    }

    static func parse(text: String, fileURL: URL, root: URL, calendar: Calendar) -> Thing? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "thing" else { return nil }
        func date(_ k: String) -> Date? { f[k].flatMap { DateText.parse($0, calendar: calendar) } }
        let priceText = f["price"] ?? ""
        let currency = priceText.range(of: #"[A-Za-z¥$€£]+"#, options: .regularExpression).map { String(priceText[$0]) } ?? ""
        let photo = f["photo"].flatMap { p -> URL? in
            guard !p.isEmpty else { return nil }
            return p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
        }
        return Thing(fileURL: fileURL,
                     name: f["name"] ?? f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                     category: f["category"] ?? "其他", location: f["location"] ?? "", box: f["box"] ?? "",
                     status: f["status"] ?? "在用", lentTo: f["lent_to"] ?? "",
                     price: HealthStore.number(priceText), currency: currency.isEmpty ? "USD" : currency,
                     purchased: date("purchased"), store: f["store"] ?? "",
                     warrantyUntil: date("warranty_until"), returnUntil: date("return_until"), serial: f["serial"] ?? "",
                     lasts: f["lasts"].flatMap(Interval.parse), restocked: date("restocked"),
                     maintainEvery: f["maintain_every"].flatMap(Interval.parse), maintained: date("maintained"),
                     photo: photo, detailed: f["maintenance"] == "detailed" || Frontmatter.bool(f["detailed"]) == true,
                     body: doc.body)
    }
}

/// `物品/` 目录
public struct ThingStore: Sendable {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent("物品") }

    public var photosDir: URL { root.appendingPathComponent("照片") }

    public func load(calendar: Calendar = .current) -> [Thing] {
        HealthStore.markdownFiles(in: root)
            .filter { !$0.path.hasPrefix(photosDir.path + "/") }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).flatMap { Thing.parse(text: $0, fileURL: url, root: root, calendar: calendar) }
            }
            .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }
}

/// 物品在日历上的出现
public enum ThingCalendar {
    /// 补货、保养提前几天开始出现
    public static let leadDays = 7

    public static func occurrences(_ things: [Thing], in range: DateInterval, calendar: Calendar) -> [Occurrence] {
        var out: [Occurrence] = []
        func add(_ thing: Thing, _ key: String, _ style: Occurrence.Style, _ title: String, start: Date, end: Date?) {
            let s = calendar.startOfDay(for: start)
            let e = end.map { Recurrence.endOfDay($0, calendar) }
            let span = DateInterval(start: s, end: max(e ?? Recurrence.endOfDay(s, calendar), s))
            guard span.intersects(range) else { return }
            out.append(Occurrence(id: "thing:\(thing.id)#\(key)", style: style, title: title, subtitle: "物品",
                                  start: s, end: e, allDay: true, sourceURL: thing.fileURL, location: thing.location))
        }
        for t in things where t.status != "已卖" && t.status != "丢了" {
            if let d = t.returnUntil { add(t, "return", .deadline, "退货截止：\(t.name)", start: d, end: nil) }
            if let d = t.warrantyUntil { add(t, "warranty", .deadline, "保修到期：\(t.name)", start: d, end: nil) }
            if let d = t.nextRestock(calendar: calendar) {
                let from = calendar.date(byAdding: .day, value: -leadDays, to: d) ?? d
                add(t, "restock", .window, "补货：\(t.name)", start: from, end: d)
            }
            for task in t.maintenanceTasks(calendar: calendar) {
                guard let d = task.next else { continue }
                let from = calendar.date(byAdding: .day, value: -leadDays, to: d) ?? d
                let title = task.name == "保养" ? "保养：\(t.name)" : "保养：\(t.name) · \(task.name)"
                add(t, "maint-\(task.name)", .window, title, start: from, end: d)
            }
        }
        return out
    }
}

// MARK: - 想买清单、快速记一件东西

/// 想买清单的一行
public struct WishItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var why: String
    public var price: String
    public var added: Date?
    /// 考虑中 / 买了 / 不买了
    public var result: String
    public var note: String

    public var isOpen: Bool { result.isEmpty || result == "考虑中" }
}

extension ThingStore {
    /// `物品/想买.md`：| 想买 | 为什么 | 大概多少钱 | 加入日期 | 结果 | 备注 |
    public var wishlistURL: URL { root.appendingPathComponent("想买.md") }

    public func loadWishlist(calendar: Calendar = .current) -> [WishItem] {
        guard let text = try? String(contentsOf: wishlistURL, encoding: .utf8) else { return [] }
        return Self.parseWishlist(text, calendar: calendar)
    }

    static func parseWishlist(_ text: String, calendar: Calendar) -> [WishItem] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains { $0.contains("想买") } })
        else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        let ni = idx("想买") ?? 0, wi = idx("为什么"), pi = idx("钱"), di = idx("日期"), ri = idx("结果"), oi = idx("备注")
        return t.rows.enumerated().compactMap { i, row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard !cell(ni).isEmpty else { return nil }
            return WishItem(id: i, name: cell(ni), why: cell(wi), price: cell(pi),
                            added: DateText.parse(cell(di), calendar: calendar), result: cell(ri), note: cell(oi))
        }
    }

    /// 在想买清单末尾加一行（结果 = 考虑中）；文件不存在就新建。返回改动前的内容（撤销用，新建时为 nil）。
    @discardableResult
    public func appendWish(_ name: String, now: Date = Date(), calendar: Calendar = .current) throws -> String? {
        let clean = name.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let row = "| \(clean) |  |  | \(DateText.format(now, withTime: false, calendar: calendar)) | 考虑中 |  |"
        guard let before = try? String(contentsOf: wishlistURL, encoding: .utf8) else {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let text = "---\ntype: thing-wishlist\n---\n# 想买\n\n买之前 agent 会先查：家里有没有一样或类似的、现有的还好不好用、以前买过的类似东西用得怎么样。\n\n| 想买 | 为什么 | 大概多少钱 | 加入日期 | 结果 | 备注 |\n|---|---|---|---|---|---|\n\(row)\n"
            try text.write(to: wishlistURL, atomically: true, encoding: .utf8)
            return nil
        }
        var lines = before.components(separatedBy: "\n")
        if let h = lines.firstIndex(where: { $0.hasPrefix("|") && $0.contains("想买") }) {
            var last = h
            while last + 1 < lines.count, lines[last + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") { last += 1 }
            lines.insert(row, at: last + 1)
        } else {
            lines += ["", "| 想买 | 为什么 | 大概多少钱 | 加入日期 | 结果 | 备注 |", "|---|---|---|---|---|---|", row]
        }
        try lines.joined(separator: "\n").write(to: wishlistURL, atomically: true, encoding: .utf8)
        return before
    }

    /// 快速记一件东西：“剪刀，厨房第二个抽屉” → 名称 + 位置，其余以后补。返回新文件路径。
    public func quickAdd(_ text: String, now: Date = Date(), calendar: Calendar = .current) throws -> URL {
        let parts = text.split(maxSplits: 1, whereSeparator: { $0 == "，" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.first ?? ""
        guard !name.isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
        let location = parts.count > 1 ? parts[1] : ""
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        var url = root.appendingPathComponent("\(safe).md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(safe) \(n).md"); n += 1
        }
        let lines = ["---", "type: thing", "name: \(Frontmatter.quote(name))", "category: 其他",
                     "location: \(Frontmatter.quote(location))", "status: 在用", "added_by: user",
                     "created: \(DateText.format(now, withTime: false, calendar: calendar))", "---", ""]
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

public enum ThingMatch {
    /// 已有的东西里和“想买的”相似的：名字互相包含，或者有共同的两个汉字 / 一个三个字母以上的英文词
    public static func similar(to wish: String, in things: [Thing]) -> [Thing] {
        let w = wish.lowercased()
        let wishTokens = tokens(w)
        return things.filter { t in
            let n = t.name.lowercased()
            if n.contains(w) || w.contains(n) { return true }
            return !tokens(n).isDisjoint(with: wishTokens)
        }
    }

    /// 汉字两两相邻的组合 + 英文单词（≥ 3 个字母）
    static func tokens(_ s: String) -> Set<String> {
        var out = Set<String>()
        let chars = Array(s)
        for i in 0..<max(0, chars.count - 1) where isHan(chars[i]) && isHan(chars[i + 1]) {
            out.insert(String(chars[i...i + 1]))
        }
        for word in s.split(whereSeparator: { !$0.isLetter || isHan($0) }) where word.count >= 3 {
            out.insert(String(word))
        }
        return out
    }

    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
    }
}
