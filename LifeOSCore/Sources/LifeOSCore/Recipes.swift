import Foundation

// 食谱、购物清单、备餐（都在 `健康/` 下）：
// - `食谱/{名字}.md`：一个食谱一个文件。frontmatter `type: recipe`、`name`、`meal`（早饭 / 午饭 / 加餐 / 晚饭 / 备餐）、
//   每份的 `kcal`、`protein`、`carbs`、`fat`，可选微量营养（`sodium` …，键同目标文件），`batch`（一次做几份，备餐用）；
//   正文 `## 材料` 一张表 `| 材料 | 一份用量 | 在哪买 |`，`## 做法` 编号列表，其余随意。agent 写，App 读。
// - `购物清单.md`：按“## 在哪买”分组的勾选列表 `- [ ] 土豆 400 g（孜然猪肉土豆卷 ×4）`。电脑版可以加、勾、清掉买好的；
//   手机版只能勾 / 取消（`ShoppingList.toggle`，只改那一行的勾选框）。
// - `备餐.md`：一张表 `| 做的那天 | 什么 | 做了 | 还剩 | 放哪 | 吃完期限 |`，冷藏、冷冻各一行。
//   App 可以记一批、“吃了一个”（还剩 −1，同时按食谱的营养在当天饮食表记一行）。

/// 一样材料
public struct Ingredient: Equatable, Sendable {
    public var name: String
    /// 一份用多少（原文，比如“100 g”“2 个”“1/4 包（4 oz）”“适量”）
    public var amount: String
    /// 在哪买（超市 / Weee / Amazon / 家里有 …）
    public var store: String

    public init(name: String, amount: String, store: String) {
        self.name = name; self.amount = amount; self.store = store
    }

    /// 开头的数量和单位：“100 g” → (100, "g")，“1/4 包（4 oz）” → (0.25, "包")，“2 个” → (2, "个")；不是数字开头就 nil
    public var quantity: (value: Double, unit: String)? {
        Ingredient.parseQuantity(amount)
    }

    static func parseQuantity(_ s: String) -> (value: Double, unit: String)? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "×", with: "")
        guard let r = t.range(of: #"^\d+(\.\d+)?(/\d+)?"#, options: .regularExpression) else { return nil }
        let num = String(t[r])
        let value: Double
        if num.contains("/") {
            let p = num.split(separator: "/").compactMap { Double($0) }
            guard p.count == 2, p[1] != 0 else { return nil }
            value = p[0] / p[1]
        } else {
            guard let v = Double(num) else { return nil }
            value = v
        }
        // 单位：数字后面到空格 / 括号为止
        let rest = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        let unit = rest.prefix { !" （(，,".contains($0) }
        return (value, String(unit))
    }
}

/// 一个食谱
public struct Recipe: Equatable, Sendable, Identifiable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var name: String
    /// 早饭 / 午饭 / 加餐 / 晚饭 / 备餐
    public var meal: String
    /// 一次做几份（备餐用）；没写 = 1
    public var batch: Int
    /// 每份的营养；没写热量 = nil
    public var nutrition: Nutrition?
    public var ingredients: [Ingredient]
    public var steps: [String]
    /// 正文里材料、做法以外的部分（备注、变化）
    public var notes: String

    public static let mealOrder = ["早饭", "午饭", "加餐", "晚饭", "备餐"]
}

extension HealthStore {
    public var recipesDir: URL { root.appendingPathComponent("食谱") }
    public var shoppingURL: URL { root.appendingPathComponent("购物清单.md") }
    public var prepURL: URL { root.appendingPathComponent("备餐.md") }

    public func loadRecipes() -> [Recipe] {
        Self.markdownFiles(in: recipesDir).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self.parseRecipe(text, url: url)
        }.sorted {
            let a = Recipe.mealOrder.firstIndex(of: $0.meal) ?? 99, b = Recipe.mealOrder.firstIndex(of: $1.meal) ?? 99
            return (a, $0.name) < (b, $1.name)
        }
    }

    static func parseRecipe(_ text: String, url: URL) -> Recipe? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "recipe" else { return nil }
        let name = f["name"].flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        var nutrition: Nutrition?
        if let kcal = f["kcal"].flatMap(number) {
            var micros: [String: Double] = [:]
            for m in Micronutrient.all { if let v = f[m.key].flatMap(number) { micros[m.key] = v } }
            nutrition = Nutrition(kcal: kcal, protein: f["protein"].flatMap(number) ?? 0, carbs: f["carbs"].flatMap(number) ?? 0,
                                  fat: f["fat"].flatMap(number) ?? 0, micros: micros)
        }
        // 按 “## ” 分段
        var sections: [(String, [String])] = [("", [])]
        for line in doc.body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") { sections.append((String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])) }
            else { sections[sections.count - 1].1.append(line) }
        }
        var ingredients: [Ingredient] = []
        var steps: [String] = []
        var notes: [String] = []
        for (title, lines) in sections {
            let body = lines.joined(separator: "\n")
            if title.hasPrefix("材料"), let t = MarkdownTable.tables(in: body).first {
                let h = t.header
                let ni = h.firstIndex { $0.contains("材料") } ?? 0
                let ai = h.firstIndex { $0.contains("用量") } ?? 1
                let si = h.firstIndex { $0.contains("买") }
                ingredients = t.rows.compactMap { c in
                    func cell(_ j: Int?) -> String { j.map { $0 < c.count ? c[$0] : "" } ?? "" }
                    let n = cell(ni)
                    return n.isEmpty ? nil : Ingredient(name: n, amount: cell(ai), store: cell(si))
                }
            } else if title.hasPrefix("做法") {
                steps = lines.compactMap { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard let r = t.range(of: #"^(\d+[.、)]|[-*])\s*"#, options: .regularExpression) else { return nil }
                    let s = String(t[r.upperBound...])
                    return s.isEmpty ? nil : s
                }
            } else if !title.isEmpty {
                let content = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { notes.append("**\(title)**\n" + content) }
            }
        }
        return Recipe(fileURL: url, name: name, meal: f["meal"] ?? "", batch: max(Int(f["batch"].flatMap(number) ?? 1), 1),
                      nutrition: nutrition, ingredients: ingredients, steps: steps, notes: notes.joined(separator: "\n\n"))
    }
}

// MARK: - 购物清单

/// 购物清单里的一项
public struct ShoppingItem: Equatable, Sendable, Identifiable {
    public var id: String { store + "|" + text + "|\(occurrence)" }
    /// 在哪买（清单里的 “## ” 标题）
    public var store: String
    /// 整行文字（不含 “- [ ] ”）
    public var text: String
    public var done: Bool
    /// 同一段里文字一模一样的第几个（从 0 数，勾没勾都算）：有重名的项时靠它找到是哪一行
    public var occurrence: Int

    public init(store: String, text: String, done: Bool, occurrence: Int = 0) {
        self.store = store; self.text = text; self.done = done; self.occurrence = occurrence
    }
}

public enum ShoppingList {
    public static let header = "---\ntype: shopping-list\n---\n# 购物清单\n\n按在哪买分组；买到了就勾上，App 里“清掉买好的”会把勾了的删掉。\n"

    public static func parse(_ text: String) -> [ShoppingItem] {
        scan(Array(text.utf8)).map(\.item)
    }

    /// 清单里的一个勾选行：解析出来的项 + 勾选框里那个字符（空格 / x / X）在文件里的字节位置
    struct Line {
        var item: ShoppingItem
        var markOffset: Int
    }

    /// 逐行扫描（按字节，`\n` 和 `\r\n` 都行）：跳过 frontmatter，“## ” 换段，`- [ ] ` / `- [x] ` / `- [X] ` 是一项。
    /// `parse` 和 `toggle` 都用它，显示的和写的一定是同一行。
    static func scan(_ bytes: [UInt8]) -> [Line] {
        // 切行：每行的 [开始, 结束)（不含 \n）
        var ranges: [Range<Int>] = []
        var start = 0
        for (i, b) in bytes.enumerated() where b == 0x0A {
            ranges.append(start..<i)
            start = i + 1
        }
        ranges.append(start..<bytes.count)
        func string(_ r: Range<Int>) -> String { String(decoding: bytes[r], as: UTF8.self) }
        func trimmed(_ r: Range<Int>) -> String {
            var s = string(r)
            if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // frontmatter（和 Frontmatter.parse 一样：第一行是 ---，到下一个 --- 为止）
        var first = 0
        if let r0 = ranges.first, trimmed(r0) == "---",
           let close = ranges.indices.dropFirst().first(where: { trimmed(ranges[$0]) == "---" }) {
            first = close + 1
        }
        var store = "其他"
        var seen: [String: Int] = [:]
        var lines: [Line] = []
        for r in ranges[first...] {
            let t = trimmed(r)
            if t.hasPrefix("## ") { store = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces); continue }
            for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where t.hasPrefix(prefix) {
                // 勾选框的位置：行首空白之后的 “- [” 再往后一个字节
                let raw = string(r)
                guard let at = raw.range(of: prefix.trimmingCharacters(in: .whitespaces)) else { break }
                let offset = r.lowerBound + raw.utf8.distance(from: raw.startIndex, to: at.lowerBound) + 3
                guard offset < r.upperBound, [0x20, 0x78, 0x58].contains(bytes[offset]) else { break }
                let text = String(t.dropFirst(prefix.count))
                let key = store + "\n" + text
                let n = seen[key, default: 0]
                seen[key] = n + 1
                lines.append(Line(item: ShoppingItem(store: store, text: text, done: done, occurrence: n), markOffset: offset))
            }
        }
        return lines
    }

    /// 几个食谱各做几份要买的东西：同名同单位的加起来，单位对不上的分开列；“家里有”的不列
    public static func items(for picks: [(recipe: Recipe, servings: Int)]) -> [ShoppingItem] {
        struct Key: Hashable { var store: String; var name: String; var unit: String? }
        var order: [Key] = []
        var totals: [Key: Double] = [:]
        var texts: [Key: String] = [:]
        var sources: [Key: [String]] = [:]
        for (recipe, n) in picks where n > 0 {
            for ing in recipe.ingredients {
                let store = ing.store.isEmpty ? "其他" : ing.store
                guard store != "家里有" else { continue }
                let q = ing.quantity
                let key = Key(store: store, name: ing.name, unit: q?.unit)
                if totals[key] == nil && texts[key] == nil { order.append(key) }
                if let q { totals[key, default: 0] += q.value * Double(n) } else { texts[key] = ing.amount }
                sources[key, default: []].append("\(recipe.name) ×\(n)")
            }
        }
        return order.map { k in
            let amount: String = {
                if let v = totals[k] {
                    let num = v == v.rounded() ? "\(Int(v))" : String(format: "%.1f", v)
                    return k.unit.map { $0.isEmpty ? num : "\(num) \($0)" } ?? num
                }
                return texts[k] ?? ""
            }()
            let from = sources[k].map { "（" + $0.joined(separator: "、") + "）" } ?? ""
            return ShoppingItem(store: k.store, text: [k.name, amount].filter { !$0.isEmpty }.joined(separator: " ") + from, done: false)
        }
    }

    /// 把新的几项加到清单里（按“在哪买”放进对应的段，没有就新建一段）；已经有一模一样还没勾的就跳过
    public static func adding(_ new: [ShoppingItem], to text: String?) -> String {
        var lines = (text ?? header).components(separatedBy: "\n")
        let existing = Set(parse(text ?? "").filter { !$0.done }.map { $0.store + "|" + $0.text })
        for item in new where !existing.contains(item.store + "|" + item.text) {
            let line = "- [ ] " + item.text
            if let h = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## " + item.store }) {
                var i = h + 1
                while i < lines.count, !lines[i].hasPrefix("## ") { i += 1 }
                // 插在这一段最后一个非空行后面
                var at = i
                while at > h + 1, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
                lines.insert(line, at: at)
            } else {
                while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
                lines += ["", "## " + item.store, line]
            }
        }
        var out = lines.joined(separator: "\n")
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    /// 勾上 / 取消某一项：只改那一行勾选框里的一个字符（空格 ↔ x，`X` 取消时也变空格），其他字节原样。
    /// 按 段 + 文字 + 第几个重名 + 现在勾没勾 找那一行；找不到（或者状态和看到的不一样）返回 nil。
    public static func toggledBytes(_ item: ShoppingItem, in bytes: [UInt8]) -> [UInt8]? {
        guard let line = scan(bytes).first(where: {
            $0.item.store == item.store && $0.item.text == item.text
                && $0.item.occurrence == item.occurrence && $0.item.done == item.done
        }) else { return nil }
        var out = bytes
        out[line.markOffset] = item.done ? 0x20 : 0x78
        return out
    }

    /// 文字版（电脑版旧接口）：找不到就原样返回
    public static func toggling(_ item: ShoppingItem, in text: String) -> String {
        toggledBytes(item, in: Array(text.utf8)).map { String(decoding: $0, as: UTF8.self) } ?? text
    }

    public enum ToggleError: Error, LocalizedError {
        case replaceFailed(Int32)
        public var errorDescription: String? {
            switch self { case .replaceFailed(let e): "替换文件失败（\(String(cString: strerror(e)))）" }
        }
    }

    /// 在磁盘上勾上 / 取消一项（电脑版和手机版共用）：
    /// 1. 写之前从磁盘重新读这个文件（在 NSFileCoordinator 里，和别的进程错开）；
    /// 2. 按段 + 文字 + 重名序号 + 勾选状态找那一行，找不到 / 对不上 → 不写，返回 false；
    /// 3. 新内容先写到 `scratch`（App 自己的临时目录，不在 vault 里），再用 rename(2) 一步换掉原文件
    ///    （同一个卷上是原子的；不同卷会失败、报错，不会退回成非原子的写法）。临时文件无论成败都不留下。
    /// 不新建、不删除、不改名 vault 里的任何文件：原文件不存在就返回 false。
    /// iOS 上调用前要已经 `startAccessingSecurityScopedResource`（PhoneModel 选文件夹时一直开着）。
    @discardableResult
    public static func toggle(_ item: ShoppingItem, at url: URL,
                              scratch: URL = FileManager.default.temporaryDirectory) throws -> Bool {
        var result: Result<Bool, Error> = .success(false)
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            result = Result { try toggleNow(item, at: target, scratch: scratch) }
        }
        if let coordError { throw coordError }
        return try result.get()
    }

    private static func toggleNow(_ item: ShoppingItem, at url: URL, scratch: URL) throws -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return false }
        let bytes = [UInt8](try Data(contentsOf: url))
        guard let out = toggledBytes(item, in: bytes) else { return false }
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let tmp = scratch.appendingPathComponent("lifeos-shopping-\(UUID().uuidString).md")
        defer { try? fm.removeItem(at: tmp) }
        try Data(out).write(to: tmp)
        // 保留原文件的权限
        if let perm = try? fm.attributesOfItem(atPath: url.path)[.posixPermissions] {
            try? fm.setAttributes([.posixPermissions: perm], ofItemAtPath: tmp.path)
        }
        let rc = tmp.withUnsafeFileSystemRepresentation { src in
            url.withUnsafeFileSystemRepresentation { dst in rename(src!, dst!) }
        }
        guard rc == 0 else { throw ToggleError.replaceFailed(errno) }
        return true
    }

    /// 删掉勾了的；删完空了的段标题也删
    public static func clearingDone(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return !(t.hasPrefix("- [x] ") || t.hasPrefix("- [X] "))
        }
        var i = 0
        while i < lines.count {
            if lines[i].hasPrefix("## ") {
                var j = i + 1
                while j < lines.count, lines[j].trimmingCharacters(in: .whitespaces).isEmpty { j += 1 }
                if j >= lines.count || lines[j].hasPrefix("## ") { lines.removeSubrange(i..<j); continue }
            }
            i += 1
        }
        var out = lines.joined(separator: "\n")
        while out.hasSuffix("\n\n") { out.removeLast() }
        return out.hasSuffix("\n") ? out : out + "\n"
    }
}

// MARK: - 备餐

/// 一批提前做好的饭（冷藏、冷冻各算一批）
public struct PrepBatch: Equatable, Sendable, Identifiable {
    public var id: String { "\(made.timeIntervalSince1970)|\(name)|\(place)" }
    public var made: Date
    public var name: String
    public var count: Int
    public var left: Int
    /// 冷藏 / 冷冻
    public var place: String
    public var useBy: Date?

    public init(made: Date, name: String, count: Int, left: Int, place: String, useBy: Date?) {
        self.made = made; self.name = name; self.count = count; self.left = left; self.place = place; self.useBy = useBy
    }

    /// 冷藏 3 天、冷冻 60 天（食谱.md“怎么存”：冷藏 3–4 天、冷冻 1–2 个月，取短的）
    public static func defaultUseBy(made: Date, place: String, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: place.contains("冻") ? 60 : 3, to: calendar.startOfDay(for: made))
    }
}

public enum MealPrep {
    static let header = "| 做的那天 | 什么 | 做了 | 还剩 | 放哪 | 吃完期限 |\n|---|---|---|---|---|---|"
    static let fileHead = "---\ntype: meal-prep\n---\n# 备餐\n\n提前做好的饭，冷藏、冷冻各一行。吃一个就把“还剩”减一（App 里点“吃了一个”会自动减，并记进当天的饮食）。\n\n"

    public static func parse(_ text: String, calendar: Calendar) -> [PrepBatch] {
        let body = Frontmatter.parse(text).body
        guard let t = MarkdownTable.tables(in: body).first(where: { $0.header.contains { $0.contains("还剩") } }) else { return [] }
        let h = t.header
        func col(_ s: String) -> Int? { h.firstIndex { $0.contains(s) } }
        return t.rows.compactMap { c in
            func cell(_ j: Int?) -> String { j.map { $0 < c.count ? c[$0] : "" } ?? "" }
            guard let made = DateText.parse(cell(col("做的那天")), calendar: calendar) else { return nil }
            let name = cell(col("什么"))
            guard !name.isEmpty else { return nil }
            let count = Int(HealthStore.number(cell(col("做了"))) ?? 0)
            let left = Int(HealthStore.number(cell(col("还剩"))) ?? Double(count))
            let place = cell(col("放哪"))
            let useBy = DateText.parse(cell(col("吃完期限")), calendar: calendar).map { calendar.startOfDay(for: $0) }
                ?? PrepBatch.defaultUseBy(made: made, place: place, calendar: calendar)
            return PrepBatch(made: calendar.startOfDay(for: made), name: name, count: count, left: left, place: place, useBy: useBy)
        }
    }

    static func row(_ b: PrepBatch, calendar: Calendar) -> String {
        let made = DateText.format(b.made, withTime: false, calendar: calendar)
        let use = b.useBy.map { DateText.format($0, withTime: false, calendar: calendar) } ?? ""
        return "| \(made) | \(b.name) | \(b.count) | \(b.left) | \(b.place) | \(use) |"
    }

    /// 加一批（加在表的最后）
    public static func adding(_ b: PrepBatch, to text: String?, calendar: Calendar) -> String {
        guard let text else { return fileHead + header + "\n" + row(b, calendar: calendar) + "\n" }
        var lines = text.components(separatedBy: "\n")
        guard let h = lines.firstIndex(where: { $0.hasPrefix("|") && $0.contains("还剩") }) else {
            return text + (text.hasSuffix("\n") ? "" : "\n") + "\n" + header + "\n" + row(b, calendar: calendar) + "\n"
        }
        var i = h + 1
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") { i += 1 }
        lines.insert(row(b, calendar: calendar), at: i)
        return lines.joined(separator: "\n")
    }

    /// 把某一批的“还剩”改成 left（按 做的那天 + 什么 + 放哪 找那一行）
    public static func settingLeft(_ b: PrepBatch, to left: Int, in text: String, calendar: Calendar) -> String {
        var lines = text.components(separatedBy: "\n")
        for i in lines.indices where lines[i].hasPrefix("|") {
            let row = parse(fileHead + header + "\n" + lines[i], calendar: calendar).first
            guard let row, row.made == b.made, row.name == b.name, row.place == b.place else { continue }
            var updated = row
            updated.left = max(left, 0)
            lines[i] = Self.row(updated, calendar: calendar)
            break
        }
        return lines.joined(separator: "\n")
    }
}

extension HealthStore {
    public func loadShopping() -> [ShoppingItem] {
        (try? String(contentsOf: shoppingURL, encoding: .utf8)).map(ShoppingList.parse) ?? []
    }

    public func loadPrep(calendar: Calendar = .current) -> [PrepBatch] {
        (try? String(contentsOf: prepURL, encoding: .utf8)).map { MealPrep.parse($0, calendar: calendar) } ?? []
    }
}
