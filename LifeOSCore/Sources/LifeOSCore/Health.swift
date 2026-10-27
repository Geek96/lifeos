import Foundation

// 健康插件：数据都在 vault 的 `健康/` 下，由 agent 写、App 读；
// App 唯一会写的是在当天的饮食表里追加一行“还没估算”的记录。

/// 热量与三大营养素（克）
public struct Nutrition: Equatable, Sendable {
    public var kcal: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    /// 微量营养等：键见 `Micronutrient.all`（sodium、fiber、sugar …）
    public var micros: [String: Double]

    public init(kcal: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, micros: [String: Double] = [:]) {
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.micros = micros
    }

    public static let zero = Nutrition()

    public static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        Nutrition(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat,
                  micros: a.micros.merging(b.micros, uniquingKeysWith: +))
    }
}

/// 追踪的微量营养素（和钠、糖、纤维）。饮食表的列名、目标文件的键都按这里。
public struct Micronutrient: Sendable, Identifiable {
    public var id: String { key }
    /// 目标文件 frontmatter 里的键
    public let key: String
    /// 饮食表的列名（也是显示名）
    public let label: String
    public let unit: String
    /// true = 上限（不要超过），false = 目标（尽量吃到）
    public let isLimit: Bool
    /// 列名的其他写法
    public let aliases: [String]

    public static let all: [Micronutrient] = [
        .init(key: "sodium", label: "钠", unit: "mg", isLimit: true, aliases: ["钠"]),
        .init(key: "sugar", label: "添加糖", unit: "g", isLimit: true, aliases: ["添加糖", "糖"]),
        .init(key: "fiber", label: "纤维", unit: "g", isLimit: false, aliases: ["纤维", "膳食纤维"]),
        .init(key: "potassium", label: "钾", unit: "mg", isLimit: false, aliases: ["钾"]),
        .init(key: "calcium", label: "钙", unit: "mg", isLimit: false, aliases: ["钙"]),
        .init(key: "iron", label: "铁", unit: "mg", isLimit: false, aliases: ["铁"]),
        .init(key: "magnesium", label: "镁", unit: "mg", isLimit: false, aliases: ["镁"]),
        .init(key: "zinc", label: "锌", unit: "mg", isLimit: false, aliases: ["锌"]),
        .init(key: "vitamin_c", label: "维C", unit: "mg", isLimit: false, aliases: ["维C", "维生素C", "维 C"]),
        .init(key: "vitamin_d", label: "维D", unit: "μg", isLimit: false, aliases: ["维D", "维生素D", "维 D"]),
        .init(key: "vitamin_a", label: "维A", unit: "μg", isLimit: false, aliases: ["维A", "维生素A"]),
        .init(key: "b12", label: "B12", unit: "μg", isLimit: false, aliases: ["B12", "维B12", "维生素B12"]),
        .init(key: "folate", label: "叶酸", unit: "μg", isLimit: false, aliases: ["叶酸"]),
        .init(key: "omega3", label: "Omega-3", unit: "g", isLimit: false, aliases: ["Omega-3", "omega-3", "Omega3"]),
    ]

    public static func byKey(_ k: String) -> Micronutrient? { all.first { $0.key == k } }

    /// 表头 → 微量营养素（按列名匹配，最长的别名优先，免得“糖”吃掉“添加糖”之外的列）
    static func forHeader(_ h: String) -> Micronutrient? {
        let t = h.trimmingCharacters(in: .whitespaces)
        return all.first { m in m.aliases.contains { t == $0 || t.hasPrefix($0 + "（") || t.hasPrefix($0 + "(") || t.hasPrefix($0 + " ") } }
    }
}

/// 饮食表里的一行。数字为空 = 还没估算（App 里直接记的那种）。
public struct Meal: Equatable, Sendable, Identifiable {
    public var id: Int
    public var time: String
    public var text: String
    public var nutrition: Nutrition?

    public var isEstimated: Bool { nutrition != nil }
}

/// 一天的饮食
public struct DietDay: Equatable, Sendable {
    public var date: Date
    public var meals: [Meal]

    public var total: Nutrition { meals.compactMap(\.nutrition).reduce(.zero, +) }
    public var pendingCount: Int { meals.filter { !$0.isEstimated }.count }
}

/// 一次复测：frontmatter 平铺的字段，保持文件里的顺序
public struct HealthTest: Equatable, Sendable, Identifiable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var date: Date
    public var title: String
    public var fields: [(key: String, value: String)]

    public static func == (a: HealthTest, b: HealthTest) -> Bool {
        a.fileURL == b.fileURL && a.date == b.date && a.title == b.title
            && a.fields.map(\.key) == b.fields.map(\.key) && a.fields.map(\.value) == b.fields.map(\.value)
    }

    /// 复测里有意义的指标（中文名）；没写的跳过
    public static let labels: [(key: String, label: String)] = [
        ("weight", "体重"), ("waist", "腰围"), ("mile", "1 英里"), ("pushups", "俯卧撑"), ("bench", "卧推"),
    ]
}

/// 健康插件的一次快照
public struct HealthSnapshot: Equatable, Sendable {
    public var targets: Nutrition?
    public var days: [DietDay]
    public var tests: [HealthTest]
    public var body: HealthBody = .empty
    /// 训练记录，新的在前
    public var sessions: [HealthSession] = []
    /// 动作（`健康/动作/`）
    public var exercises: [Exercise] = []
    /// 学期一周训练计划（`健康/训练计划.md`）
    public var plan: WeekPlan = .empty
    /// 睡眠（`健康/睡眠/`），旧的在前
    public var sleep: [SleepNight] = []

    public static let empty = HealthSnapshot(targets: nil, days: [], tests: [])

    public func day(_ date: Date, calendar: Calendar) -> DietDay {
        days.first { calendar.isDate($0.date, inSameDayAs: date) } ?? DietDay(date: calendar.startOfDay(for: date), meals: [])
    }
}

/// `健康/` 目录的读写
public struct HealthStore: Sendable {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent("健康") }

    public var targetsURL: URL { root.appendingPathComponent("目标.md") }
    public var dietDir: URL { root.appendingPathComponent("饮食") }
    public var testsDir: URL { root.appendingPathComponent("复测") }

    public func dietURL(_ date: Date, calendar: Calendar = .current) -> URL {
        dietDir.appendingPathComponent("\(DateText.format(date, withTime: false, calendar: calendar)).md")
    }

    public func load(calendar: Calendar = .current) -> HealthSnapshot {
        HealthSnapshot(targets: loadTargets(), days: loadDays(calendar: calendar), tests: loadTests(calendar: calendar),
                       body: loadBody(calendar: calendar), sessions: loadSessions(calendar: calendar),
                       exercises: loadExercises(calendar: calendar), plan: loadWeekPlan(), sleep: loadSleep(calendar: calendar))
    }

    // MARK: - 目标

    public func loadTargets() -> Nutrition? {
        guard let text = try? String(contentsOf: targetsURL, encoding: .utf8) else { return nil }
        return Self.parseTargets(text)
    }

    static func parseTargets(_ text: String) -> Nutrition? {
        let f = Frontmatter.parse(text).fields
        guard let kcal = f["kcal"].flatMap(Self.number) else { return nil }
        var micros: [String: Double] = [:]
        for m in Micronutrient.all { if let v = f[m.key].flatMap(Self.number) { micros[m.key] = v } }
        return Nutrition(kcal: kcal, protein: f["protein"].flatMap(Self.number) ?? 0,
                         carbs: f["carbs"].flatMap(Self.number) ?? 0, fat: f["fat"].flatMap(Self.number) ?? 0, micros: micros)
    }

    // MARK: - 饮食

    public func loadDays(calendar: Calendar = .current) -> [DietDay] {
        Self.markdownFiles(in: dietDir).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let f = Frontmatter.parse(text).fields
            let dateText = f["date"] ?? url.deletingPathExtension().lastPathComponent
            guard let date = DateText.parse(dateText, calendar: calendar) else { return nil }
            return DietDay(date: calendar.startOfDay(for: date), meals: Self.parseMeals(text))
        }.sorted { $0.date < $1.date }
    }

    /// 解析正文里第一张表头含“吃了什么”的表：时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪
    static func parseMeals(_ text: String) -> [Meal] {
        let body = Frontmatter.parse(text).body
        let table = MarkdownTable.tables(in: body).first { $0.header.contains { $0.contains("吃了什么") } }
        guard let table else { return [] }
        // 按列名找列：以后加列（钠、维D …）不用改格式
        let h = table.header
        func col(_ name: String) -> Int? { h.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix(name) } }
        let ti = col("时间") ?? 0, wi = col("吃了什么") ?? 1
        let ki = col("热量") ?? 2, pi = col("蛋白质") ?? 3, ci = col("碳水") ?? 4, fi = col("脂肪") ?? 5
        let microCols: [(Int, Micronutrient)] = h.enumerated().compactMap { j, name in Micronutrient.forHeader(name).map { (j, $0) } }
        return table.rows.enumerated().compactMap { i, cells in
            func cell(_ j: Int) -> String { j < cells.count ? cells[j] : "" }
            let text = cell(wi).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            var nutrition: Nutrition?
            if let kcal = Self.number(cell(ki)) {
                var micros: [String: Double] = [:]
                for (j, m) in microCols { if let v = Self.number(cell(j)) { micros[m.key] = v } }
                nutrition = Nutrition(kcal: kcal, protein: Self.number(cell(pi)) ?? 0, carbs: Self.number(cell(ci)) ?? 0,
                                      fat: Self.number(cell(fi)) ?? 0, micros: micros)
            }
            return Meal(id: i, time: cell(ti).trimmingCharacters(in: .whitespaces), text: text, nutrition: nutrition)
        }
    }

    /// 在当天的饮食表里追加一行还没估算的记录；文件不存在就新建。返回改动前的内容（撤销用，新建时为 nil）。
    @discardableResult
    public func appendMeal(_ text: String, at date: Date, calendar: Calendar = .current) throws -> String? {
        let clean = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "/")
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let url = dietURL(date, calendar: calendar)
        let time = Self.timeFormatter(calendar).string(from: date)
        let row = "| \(time) | \(clean) |" + String(repeating: "  |", count: 4 + Self.defaultMicroColumns.count)
        let fm = FileManager.default
        guard let before = try? String(contentsOf: url, encoding: .utf8) else {
            try fm.createDirectory(at: dietDir, withIntermediateDirectories: true)
            try Self.newDayFile(date, calendar: calendar, firstRow: row).write(to: url, atomically: true, encoding: .utf8)
            return nil
        }
        try Self.insertRow(row, into: before).write(to: url, atomically: true, encoding: .utf8)
        return before
    }

    /// 新建饮食表默认带的微量营养列
    static let defaultMicroColumns = ["钠", "添加糖", "纤维", "钾", "钙", "铁", "维C", "维D"]

    static let tableHeader: String = {
        let cols = ["时间", "吃了什么", "热量", "蛋白质", "碳水", "脂肪"] + defaultMicroColumns
        return "| " + cols.joined(separator: " | ") + " |\n|" + String(repeating: "---|", count: cols.count)
    }()

    static func newDayFile(_ date: Date, calendar: Calendar, firstRow: String) -> String {
        let day = DateText.format(date, withTime: false, calendar: calendar)
        return "---\ntype: health-diet\ndate: \(day)\n---\n# \(day) 饮食\n\n\(tableHeader)\n\(firstRow)\n"
    }

    /// 把一行插到饮食表最后一行之后；找不到表就在正文末尾新建一张
    static func insertRow(_ row: String, into text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let headerIndex = lines.firstIndex(where: { $0.hasPrefix("|") && $0.contains("吃了什么") }) {
            var last = headerIndex
            while last + 1 < lines.count, lines[last + 1].trimmingCharacters(in: .whitespaces).hasPrefix("|") { last += 1 }
            lines.insert(row, at: last + 1)
            return lines.joined(separator: "\n")
        }
        var out = text
        if !out.hasSuffix("\n") { out += "\n" }
        return out + "\n\(tableHeader)\n\(row)\n"
    }

    // MARK: - 复测

    public func loadTests(calendar: Calendar = .current) -> [HealthTest] {
        Self.markdownFiles(in: testsDir).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self.parseTest(text, fileURL: url, calendar: calendar)
        }.sorted { $0.date < $1.date }
    }

    static func parseTest(_ text: String, fileURL: URL, calendar: Calendar) -> HealthTest? {
        let doc = Frontmatter.parse(text)
        guard doc.fields["type"] == "health-test",
              let date = doc.fields["date"].flatMap({ DateText.parse($0, calendar: calendar) }) else { return nil }
        // 按文件里的顺序取出指标字段
        let skip: Set<String> = ["type", "date", "title", "added_by", "created"]
        let lines = text.components(separatedBy: "\n")
        var ordered: [(key: String, value: String)] = []
        var seen = Set<String>()
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            for line in lines.dropFirst() {
                if line.trimmingCharacters(in: .whitespaces) == "---" { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                guard !skip.contains(key), !seen.contains(key), let value = doc.fields[key], !value.isEmpty else { continue }
                seen.insert(key)
                ordered.append((key, value))
            }
        }
        let title = doc.fields["title"] ?? fileURL.deletingPathExtension().lastPathComponent
        return HealthTest(fileURL: fileURL, date: calendar.startOfDay(for: date), title: title, fields: ordered)
    }

    // MARK: - 工具

    /// 取单元格里的第一个数字：“~390”“20 g”“2,500” 都行；空或没有数字 = nil
    public static func number(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: "")
        guard let r = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(t[r])
    }

    static func timeFormatter(_ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }

    static func markdownFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "md" }
    }
}

/// 训练事项正文里的“练什么 / 跑多远”
public enum TrainingPlan {
    /// 正文里第一个带表格的 `## ` 小节：标题 + 表格每一行（去掉表头）
    public static func firstTable(in body: String) -> (heading: String, header: [String], rows: [[String]])? {
        var heading = ""
        var sectionLines: [String] = []
        func flush() -> (String, [String], [[String]])? {
            guard let t = MarkdownTable.tables(in: sectionLines.joined(separator: "\n")).first else { return nil }
            return (heading, t.header, t.rows)
        }
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if let found = flush() { return found }
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                sectionLines = []
            } else {
                sectionLines.append(line)
            }
        }
        return flush()
    }

    /// 表格第一列以 “M/d” 开头（如“10/27 那一周”“11/14”）时，只留这次训练对应的那一行：
    /// 日期 ≤ 这天、且相差不到 7 天的最后一行。第一列不是日期就原样返回。
    public static func rows(_ rows: [[String]], for date: Date, calendar: Calendar) -> [[String]] {
        let year = calendar.component(.year, from: date)
        let day = calendar.startOfDay(for: date)
        let dated: [(Date, [String])] = rows.compactMap { row in
            guard let first = row.first,
                  let r = first.range(of: #"^\s*\d{1,2}/\d{1,2}"#, options: .regularExpression) else { return nil }
            let parts = first[r].trimmingCharacters(in: .whitespaces).split(separator: "/").compactMap { Int($0) }
            guard parts.count == 2,
                  let d = calendar.date(from: DateComponents(year: year, month: parts[0], day: parts[1])) else { return nil }
            return (d, row)
        }
        guard dated.count == rows.count, !dated.isEmpty else { return rows }
        let match = dated.last { $0.0 <= day && day.timeIntervalSince($0.0) < 7 * 86400 }
        return match.map { [$0.1] } ?? rows
    }
}

/// 极简 Markdown 表格解析：连续的 `|` 行，第二行是分隔线
public enum MarkdownTable {
    public struct Table: Equatable, Sendable {
        public var header: [String]
        public var rows: [[String]]
    }

    public static func tables(in text: String) -> [Table] {
        var result: [Table] = []
        var block: [String] = []
        func flush() {
            defer { block = [] }
            guard block.count >= 2, isSeparator(block[1]) else { return }
            result.append(Table(header: cells(block[0]), rows: block.dropFirst(2).map(cells)))
        }
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { block.append(t) } else { flush() }
        }
        flush()
        return result
    }

    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func isSeparator(_ line: String) -> Bool {
        let c = cells(line)
        return !c.isEmpty && c.allSatisfy { cell in !cell.isEmpty && cell.allSatisfy { "-:".contains($0) } }
    }
}

// MARK: - 身体与训练记录

/// 现在的身体数据：`健康/身体.md` 的 frontmatter，按文件顺序
public struct HealthBody: Equatable, Sendable {
    public var updated: Date?
    public var fields: [Metric]

    public struct Metric: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var value: String
    }

    public static let empty = HealthBody(updated: nil, fields: [])

    /// 已知指标：中文名 + 分组（身体 / 力量 / 耐力）
    public static let known: [String: (label: String, group: String)] = [
        "height": ("身高", "身体"), "weight": ("体重", "身体"), "waist": ("腰围", "身体"), "bodyfat": ("体脂", "身体"),
        "resting_hr": ("静息心率", "身体"),
        "bench": ("卧推", "力量"), "squat": ("深蹲", "力量"), "deadlift": ("硬拉", "力量"), "ohp": ("肩推", "力量"),
        "pullups": ("引体向上", "力量"), "pushups": ("俯卧撑", "力量"),
        "mile": ("1 英里", "耐力"), "5k": ("5 km", "耐力"), "10k": ("10 km", "耐力"), "longest_run": ("最长一次跑", "耐力"),
    ]

    public static func label(_ key: String) -> String { known[key]?.label ?? key }
    public static func group(_ key: String) -> String { known[key]?.group ?? "其他" }
}

/// 一次训练记录：`健康/训练记录/*.md`
public struct HealthSession: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case run, strength, other }

    public var id: String { fileURL.path }
    public var fileURL: URL
    public var date: Date
    public var kind: Kind
    public var title: String
    /// 跑步：公里
    public var distanceKm: Double?
    /// 用时（分钟）
    public var minutes: Double?
    /// 力量：总训练量（lb × 次），frontmatter 没写就按正文表格算
    public var volume: Double?
    /// 正文第一张表（每组、每段）
    public var table: MarkdownTable.Table?
    public var note: String

    /// 配速：分钟 / 公里
    public var pace: Double? {
        guard let d = distanceKm, d > 0, let m = minutes else { return nil }
        return m / d
    }
}

/// 某一周的汇总
public struct WeekStats: Equatable, Sendable, Identifiable {
    public var id: Date { weekStart }
    public var weekStart: Date
    public var sessions: Int
    public var runKm: Double
    /// 有距离也有用时的跑步：用来算平均配速
    public var timedKm: Double
    public var timedMinutes: Double
    public var volume: Double

    /// 这周跑步的平均配速（分钟 / 公里）
    public var pace: Double? { timedKm > 0 ? timedMinutes / timedKm : nil }

    /// 按周（日历的周起始日）汇总，最早的在前；中间没有记录的周补 0
    public static func compute(_ sessions: [HealthSession], calendar: Calendar) -> [WeekStats] {
        guard let first = sessions.map(\.date).min(), let last = sessions.map(\.date).max(),
              var week = calendar.dateInterval(of: .weekOfYear, for: first)?.start else { return [] }
        var result: [WeekStats] = []
        while week <= last {
            let end = calendar.date(byAdding: .day, value: 7, to: week) ?? week.addingTimeInterval(7 * 86400)
            let inWeek = sessions.filter { $0.date >= week && $0.date < end }
            let runs = inWeek.filter { $0.kind == .run }
            let timed = runs.filter { $0.distanceKm != nil && $0.minutes != nil }
            result.append(WeekStats(weekStart: week, sessions: inWeek.count,
                                    runKm: runs.compactMap(\.distanceKm).reduce(0, +),
                                    timedKm: timed.compactMap(\.distanceKm).reduce(0, +),
                                    timedMinutes: timed.compactMap(\.minutes).reduce(0, +),
                                    volume: inWeek.compactMap(\.volume).reduce(0, +)))
            week = end
        }
        return result
    }
}

extension HealthStore {
    public var bodyURL: URL { root.appendingPathComponent("身体.md") }
    public var sessionsDir: URL { root.appendingPathComponent("训练记录") }

    public func loadBody(calendar: Calendar = .current) -> HealthBody {
        guard let text = try? String(contentsOf: bodyURL, encoding: .utf8) else { return .empty }
        return Self.parseBody(text, calendar: calendar)
    }

    static func parseBody(_ text: String, calendar: Calendar) -> HealthBody {
        let doc = Frontmatter.parse(text)
        let skip: Set<String> = ["type", "updated", "title", "added_by", "created"]
        let fields = orderedKeys(text).filter { !skip.contains($0) }.compactMap { key -> HealthBody.Metric? in
            guard let v = doc.fields[key], !v.isEmpty else { return nil }
            return HealthBody.Metric(key: key, value: v)
        }
        return HealthBody(updated: doc.fields["updated"].flatMap { DateText.parse($0, calendar: calendar) }, fields: fields)
    }

    public func loadSessions(calendar: Calendar = .current) -> [HealthSession] {
        Self.markdownFiles(in: sessionsDir).compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Self.parseSession(text, fileURL: url, calendar: calendar)
        }.sorted { $0.date > $1.date }
    }

    static func parseSession(_ text: String, fileURL: URL, calendar: Calendar) -> HealthSession? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "health-session", let date = f["date"].flatMap({ DateText.parse($0, calendar: calendar) }) else { return nil }
        let table = MarkdownTable.tables(in: doc.body).first
        let kind = HealthSession.Kind(rawValue: f["kind"]?.lowercased() ?? "") ?? .other
        let volume = f["volume"].flatMap(number) ?? table.flatMap(volume(of:))
        let note = doc.body.components(separatedBy: "\n")
            .filter { let t = $0.trimmingCharacters(in: .whitespaces); return !t.isEmpty && !t.hasPrefix("|") && !t.hasPrefix("#") }
            .joined(separator: "\n")
        return HealthSession(fileURL: fileURL, date: date, kind: kind,
                             title: f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                             distanceKm: f["distance"].flatMap(number), minutes: f["duration"].flatMap(minutes),
                             volume: volume, table: table, note: note)
    }

    /// 力量训练量：表里每行 重量(lb) × 组 × 次；表头要有“重量”和“组”
    static func volume(of table: MarkdownTable.Table) -> Double? {
        guard let w = table.header.firstIndex(where: { $0.contains("重量") }),
              let sr = table.header.firstIndex(where: { $0.contains("组") }) else { return nil }
        let total = table.rows.reduce(0.0) { sum, row in
            guard row.count > max(w, sr), let weight = number(row[w]) else { return sum }
            let parts = row[sr].replacingOccurrences(of: "x", with: "×").replacingOccurrences(of: "X", with: "×")
                .replacingOccurrences(of: "*", with: "×").split(separator: "×").compactMap { number(String($0)) }
            guard parts.count == 2 else { return sum }
            return sum + weight * parts[0] * parts[1]
        }
        return total > 0 ? total : nil
    }

    /// 用时：“13:20”（分:秒）、“1:05:30”、“25 min”、“25”
    public static func minutes(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ":").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, let m = parts[0], let sec = parts[1] { return m + sec / 60 }
        if parts.count == 3, let h = parts[0], let m = parts[1], let sec = parts[2] { return h * 60 + m + sec / 60 }
        return number(t)
    }

    /// frontmatter 的键，按文件里出现的顺序
    static func orderedKeys(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        var keys: [String] = []
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !keys.contains(key) { keys.append(key) }
        }
        return keys
    }
}

/// 配速、用时的显示
public enum HealthFormat {
    /// 6.5 → “6:30”
    public static func minutesText(_ m: Double) -> String {
        let total = Int((m * 60).rounded())
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
                             : String(format: "%d:%02d", total / 60, total % 60)
    }
}
