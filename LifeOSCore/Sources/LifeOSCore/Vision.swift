import Foundation

// 远景插件：`远景/愿景/`（宏大的方向）、`远景/项目/`（具体能做完的事，可以挂一个愿景）、
// `远景/奇思妙想/`（随想，可以升级成项目）。都由 agent 写；App 只读，唯一会写的是项目步骤的勾选。

/// 模糊时间：“2026-12-15”“2026-12”“2026-12 中旬”“2027 春”“2027 上半年”“2028” → 一段时间。
/// 解析不了的（“寒假前”）返回 nil，界面上照原样显示文字。
public enum FuzzyTime {
    public static func parse(_ raw: String, calendar: Calendar = .current) -> DateInterval? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if let d = DateText.parse(s, calendar: calendar) {
            let day = calendar.startOfDay(for: d)
            return DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        }
        // “2027年3月下旬”“2027 年 3 月” → “2027-3 下旬”
        s = s.replacingOccurrences(of: "年", with: "-").replacingOccurrences(of: "月", with: " ")
            .replacingOccurrences(of: "\u{3000}", with: " ")
        // “2026-12中旬”“2027春”：数字和后面的字之间补一个空格
        s = s.replacingOccurrences(of: "(\\d)([^\\d\\s-])", with: "$1 $2", options: .regularExpression)
        let scanner = s.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init)
        guard let first = scanner.first, first.count == 4, let year = Int(first) else { return nil }
        var rest = Array(scanner.dropFirst())
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date? {
            calendar.date(from: DateComponents(year: y, month: m, day: d))
        }
        func interval(_ a: Date?, _ b: Date?) -> DateInterval? {
            guard let a, let b, b > a else { return nil }
            return DateInterval(start: a, end: b)
        }
        // 年 + 月（+ 旬）
        if let m = rest.first.flatMap({ Int($0) }), (1...12).contains(m) {
            rest.removeFirst()
            guard let monthStart = date(year, m, 1),
                  let next = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }
            switch rest.first ?? "" {
            case "上旬", "初": return interval(monthStart, date(year, m, 11))
            case "中旬", "中": return interval(date(year, m, 11), date(year, m, 21))
            case "下旬", "底", "末": return interval(date(year, m, 21), next)
            case "": return interval(monthStart, next)
            default: return nil
            }
        }
        // 年 + 季节 / 半年
        switch rest.first ?? "" {
        case "": return interval(date(year, 1, 1), date(year + 1, 1, 1))
        case "春", "春天", "春季": return interval(date(year, 3, 1), date(year, 6, 1))
        case "夏", "夏天", "夏季": return interval(date(year, 6, 1), date(year, 9, 1))
        case "秋", "秋天", "秋季": return interval(date(year, 9, 1), date(year, 12, 1))
        case "冬", "冬天", "冬季": return interval(date(year, 12, 1), date(year + 1, 3, 1))
        case "上半年": return interval(date(year, 1, 1), date(year, 7, 1))
        case "下半年": return interval(date(year, 7, 1), date(year + 1, 1, 1))
        default: return nil
        }
    }

    /// 是不是确切的某一天（能上日历）
    public static func exactDay(_ raw: String, calendar: Calendar = .current) -> Date? {
        DateText.parse(raw, calendar: calendar).map { calendar.startOfDay(for: $0) }
    }
}

/// 标签：“美国、Atlanta · 公园, 骑车” → 拆开
enum Tags {
    static func split(_ s: String) -> [String] {
        s.components(separatedBy: CharacterSet(charactersIn: "、,，·/#"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// 愿景上的一个 checkpoint
public struct Checkpoint: Equatable, Sendable, Identifiable {
    public enum Result: String, Sendable {
        case reached = "到了", partly = "差一点", missed = "没到", changed = "改了计划", none = ""
    }
    public var id: Int
    /// 原文，可以是模糊的
    public var when: String
    public var interval: DateInterval?
    public var text: String
    public var result: Result
    /// 过了以后写的一句话
    public var note: String

    static func result(_ s: String) -> Result {
        if s.isEmpty { return .none }
        if s.contains("差") || s.contains("部分") { return .partly }
        if s.contains("没") || s.contains("未") { return .missed }
        if s.contains("改") || s.contains("调整") { return .changed }
        if s.contains("到") || s.contains("达成") || s.contains("完成") { return .reached }
        return .none
    }
}

/// 清单型愿景（旅行这类平铺的）里的一个地点
public struct VisionPlace: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var visited: Bool
    public var tags: [String]
    /// 什么时候去的 / 计划什么时候去（原文）
    public var when: String
    public var photos: [URL]
    public var note: String
    /// 对应的出行文件（“行程”列，写文件名或 [[链接]]）
    public var trip: String
}

public struct Vision: Equatable, Sendable, Identifiable {
    /// 时间型：时间甬道 + checkpoint；清单型：平铺的条目加标签（比如去过 / 想去的地方）
    public enum Shape: String, Sendable { case timeline, list }

    public var id: String { fileURL.path }
    public var fileURL: URL
    public var title: String
    /// 一句话
    public var summary: String
    public var shape: Shape
    /// 酝酿中 / 进行中 / 搁置 / 实现了 / 放下了
    public var status: String
    public var start: String
    public var target: String
    public var tags: [String]
    public var body: String
    public var checkpoints: [Checkpoint]
    public var places: [VisionPlace]

    /// 甬道覆盖的时间：起点到目标，包含所有 checkpoint
    public func span(calendar: Calendar) -> DateInterval? {
        let parts = [FuzzyTime.parse(start, calendar: calendar), FuzzyTime.parse(target, calendar: calendar)].compactMap { $0 }
            + checkpoints.compactMap(\.interval)
        guard let s = parts.map(\.start).min(), let e = parts.map(\.end).max(), e > s else { return nil }
        return DateInterval(start: s, end: e)
    }

    /// 下一个还没过去的 checkpoint
    public func nextCheckpoint(now: Date) -> Checkpoint? {
        checkpoints.filter { ($0.interval?.end ?? .distantFuture) > now && $0.result == .none }
            .min { ($0.interval?.start ?? .distantFuture) < ($1.interval?.start ?? .distantFuture) }
    }

    public func section(_ name: String) -> String { Trip.section(name, in: body) }

    static func parse(text: String, fileURL: URL, root: URL, calendar: Calendar) -> Vision? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "vision" else { return nil }
        let body = doc.body
        return Vision(fileURL: fileURL, title: f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                      summary: f["summary"].flatMap { $0.isEmpty ? nil : $0 } ?? Vision.quote(body),
                      shape: Shape(rawValue: f["shape"] ?? "") ?? .timeline, status: f["status"] ?? "进行中",
                      start: f["start"] ?? "", target: f["target"] ?? "", tags: Tags.split(f["tags"] ?? ""), body: body,
                      checkpoints: parseCheckpoints(Trip.section("时间甬道", in: body), calendar: calendar),
                      places: parsePlaces(Trip.section("清单", in: body), root: root))
    }

    /// 正文第一段引用（`> 一句话`）
    static func quote(_ body: String) -> String {
        body.components(separatedBy: "\n").first { $0.hasPrefix("> ") }.map { String($0.dropFirst(2)) } ?? ""
    }

    /// | 时间 | checkpoint | 结果 | 一句话 |
    static func parseCheckpoints(_ text: String, calendar: Calendar) -> [Checkpoint] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.lowercased().contains(n) } }
        let iWhen = idx("时间") ?? 0, iText = idx("checkpoint") ?? idx("内容") ?? 1
        return t.rows.enumerated().compactMap { i, row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let when = cell(iWhen), what = cell(iText)
            guard !when.isEmpty || !what.isEmpty else { return nil }
            return Checkpoint(id: i, when: when, interval: FuzzyTime.parse(when, calendar: calendar), text: what,
                              result: Checkpoint.result(cell(idx("结果"))), note: cell(idx("一句话") ?? idx("备注")))
        }
    }

    /// | 名称 | 状态 | 标签 | 时间 | 照片 | 行程 | 备注 |（第一列叫“地方”“名称”都行）
    static func parsePlaces(_ text: String, root: URL) -> [VisionPlace] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        return t.rows.enumerated().compactMap { i, row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let name = cell(0)
            guard !name.isEmpty else { return nil }
            let status = cell(idx("状态"))
            let photos = Tags.split(cell(idx("照片")).replacingOccurrences(of: "·", with: "、"))
                .filter { $0.contains(".") }
                .map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : root.appendingPathComponent($0) }
            return VisionPlace(id: i, name: name, visited: status.contains("去过") || status.contains("做过") || status.contains("✓"),
                               tags: Tags.split(cell(idx("标签"))), when: cell(idx("时间")), photos: photos,
                               note: cell(idx("备注")), trip: VisionProject.link(cell(idx("行程"))))
        }
    }
}

/// 项目里的一步：记住它在文件里的第几行，勾选时只改这一行
public struct ProjectStep: Equatable, Sendable, Identifiable {
    public var id: Int { line }
    public var line: Int
    public var text: String
    public var done: Bool
    /// 行尾 “· 2026-10-25” 或 “· 2026-10-25 14:00”
    public var date: Date?
    public var hasTime: Bool
}

public struct VisionProject: Equatable, Sendable, Identifiable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var title: String
    /// 做完是什么样
    public var goal: String
    /// 挂在哪个愿景（愿景标题；空 = 未归类）
    public var vision: String
    /// 从哪个想法升级来的
    public var fromIdea: String
    /// 想做 / 进行中 / 暂停 / 做完了 / 放下了
    public var status: String
    public var start: String
    public var target: String
    public var tags: [String]
    public var body: String
    public var steps: [ProjectStep]
    public var log: [(date: String, text: String)]

    public static func == (a: VisionProject, b: VisionProject) -> Bool {
        a.fileURL == b.fileURL && a.body == b.body && a.title == b.title && a.goal == b.goal && a.vision == b.vision
            && a.status == b.status && a.start == b.start && a.target == b.target && a.tags == b.tags && a.fromIdea == b.fromIdea
    }

    public var doneCount: Int { steps.filter(\.done).count }
    public var progress: Double { steps.isEmpty ? 0 : Double(doneCount) / Double(steps.count) }
    public var nextStep: ProjectStep? { steps.first { !$0.done } }
    public var isClosed: Bool { status.contains("做完") || status.contains("放下") }

    public func section(_ name: String) -> String { Trip.section(name, in: body) }

    static func parse(text: String, fileURL: URL, calendar: Calendar) -> VisionProject? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "project" else { return nil }
        let body = doc.body
        let offset = text.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count
        return VisionProject(fileURL: fileURL, title: f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                             goal: f["goal"].flatMap { $0.isEmpty ? nil : $0 } ?? Vision.quote(body),
                             vision: link(f["vision"] ?? ""), fromIdea: link(f["from_idea"] ?? ""),
                             status: f["status"] ?? "进行中", start: f["start"] ?? "", target: f["target"] ?? "",
                             tags: Tags.split(f["tags"] ?? ""), body: body,
                             steps: parseSteps(body, offset: offset, calendar: calendar), log: parseLog(Trip.section("进展记录", in: body)))
    }

    /// “[[读 PhD]]” → “读 PhD”
    static func link(_ s: String) -> String {
        s.replacingOccurrences(of: "[[", with: "").replacingOccurrences(of: "]]", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).components(separatedBy: "|").first ?? ""
    }

    /// `## 步骤` 下的 `- [ ] 做什么 · 2026-10-25`
    static func parseSteps(_ body: String, offset: Int, calendar: Calendar) -> [ProjectStep] {
        var inSection = false
        var out: [ProjectStep] = []
        for (i, line) in body.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = line.dropFirst(3).trimmingCharacters(in: .whitespaces).hasPrefix("步骤")
                continue
            }
            guard inSection, let item = Trip.checkbox(line) else { continue }
            let (text, date, hasTime) = splitDate(item.text, calendar: calendar)
            out.append(ProjectStep(line: offset + i, text: text, done: item.done, date: date, hasTime: hasTime))
        }
        return out
    }

    static func splitDate(_ s: String, calendar: Calendar) -> (String, Date?, Bool) {
        guard let r = s.range(of: " · ", options: .backwards) else { return (s, nil, false) }
        let tail = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard let d = DateText.parse(tail, calendar: calendar) else { return (s, nil, false) }
        return (String(s[..<r.lowerBound]), d, DateText.hasTime(tail))
    }

    /// `- 2026-10-22 记了什么`
    static func parseLog(_ text: String) -> [(date: String, text: String)] {
        text.components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("- ") else { return nil }
            let rest = t.dropFirst(2)
            let head = rest.prefix(10)
            if head.count == 10, DateText.parse(String(head)) != nil {
                return (String(head), rest.dropFirst(10).trimmingCharacters(in: .whitespaces))
            }
            return ("", String(rest))
        }
    }
}

/// 奇思妙想
public struct Idea: Equatable, Sendable, Identifiable {
    /// 初始分类；agent 记的时候归类，不够用再加（RULES 里维护）
    public static let categories = ["软件", "Skill", "创作", "研究", "体验", "随想"]

    public var id: String { fileURL.path }
    public var fileURL: URL
    public var title: String
    public var category: String
    /// 随想 / 在琢磨 / 已变成项目 / 放下了
    public var status: String
    public var created: Date?
    public var tags: [String]
    public var vision: String
    /// 升级成的项目（项目标题）
    public var project: String
    public var body: String

    /// 卡片上显示的开头
    public var excerpt: String {
        body.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { $0.hasPrefix("> ") ? String($0.dropFirst(2)) : $0 }
            .prefix(3).joined(separator: " ")
    }

    static func parse(text: String, fileURL: URL, calendar: Calendar) -> Idea? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "idea" else { return nil }
        return Idea(fileURL: fileURL, title: f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                    category: f["category"].flatMap { $0.isEmpty ? nil : $0 } ?? "随想", status: f["status"] ?? "随想",
                    created: f["created"].flatMap { DateText.parse($0, calendar: calendar) }, tags: Tags.split(f["tags"] ?? ""),
                    vision: VisionProject.link(f["vision"] ?? ""), project: VisionProject.link(f["project"] ?? ""), body: doc.body)
    }
}

public struct VisionSnapshot: Equatable, Sendable {
    public var visions: [Vision]
    public var projects: [VisionProject]
    public var ideas: [Idea]

    public static let empty = VisionSnapshot(visions: [], projects: [], ideas: [])

    public func projects(of vision: Vision) -> [VisionProject] {
        projects.filter { $0.vision == vision.title }
    }

    /// 没挂愿景，或者挂的愿景不存在
    public var unfiledProjects: [VisionProject] {
        let titles = Set(visions.map(\.title))
        return projects.filter { !titles.contains($0.vision) }
    }
}

/// `远景/` 目录
public struct VisionStore: Sendable {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent("远景") }

    public var visionsDir: URL { root.appendingPathComponent("愿景") }
    public var projectsDir: URL { root.appendingPathComponent("项目") }
    public var ideasDir: URL { root.appendingPathComponent("奇思妙想") }
    public var photosDir: URL { root.appendingPathComponent("照片") }

    public func load(calendar: Calendar = .current) -> VisionSnapshot {
        func texts(_ dir: URL) -> [(URL, String)] {
            HealthStore.markdownFiles(in: dir).compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url, $0) } }
        }
        let visions = texts(visionsDir).compactMap { Vision.parse(text: $1, fileURL: $0, root: root, calendar: calendar) }
            .sorted { $0.title < $1.title }
        let projects = texts(projectsDir).compactMap { VisionProject.parse(text: $1, fileURL: $0, calendar: calendar) }
            .sorted { ($0.isClosed ? 1 : 0, $0.title) < ($1.isClosed ? 1 : 0, $1.title) }
        let ideas = texts(ideasDir).compactMap { Idea.parse(text: $1, fileURL: $0, calendar: calendar) }
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        return VisionSnapshot(visions: visions, projects: projects, ideas: ideas)
    }

    /// 勾选 / 取消项目的一步：只改那一行，并核对内容没变。返回改动前的全文（撤销用）。
    @discardableResult
    public func toggleStep(_ step: ProjectStep, in project: VisionProject) throws -> String {
        let before = try String(contentsOf: project.fileURL, encoding: .utf8)
        var lines = before.components(separatedBy: "\n")
        guard step.line < lines.count, let current = Trip.checkbox(lines[step.line]),
              current.text.hasPrefix(step.text) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let indent = String(lines[step.line].prefix { $0 == " " || $0 == "\t" })
        lines[step.line] = indent + (current.done ? "- [ ] " : "- [x] ") + current.text
        try lines.joined(separator: "\n").write(to: project.fileURL, atomically: true, encoding: .utf8)
        return before
    }
}

/// 远景在日历上的出现：只有项目里带日期的步骤（checkpoint 常和已有事项重合，不上日历，免得重复）
public enum VisionCalendar {
    public static func occurrences(_ snap: VisionSnapshot, in range: DateInterval, calendar: Calendar) -> [Occurrence] {
        var out: [Occurrence] = []
        for p in snap.projects where !p.status.contains("放下") {
            for step in p.steps {
                guard let d = step.date else { continue }
                let start = step.hasTime ? d : calendar.startOfDay(for: d)
                guard range.contains(start) else { continue }
                out.append(Occurrence(id: "project:\(p.id)#\(step.line)", style: .deadline, title: step.text,
                                      subtitle: "项目：\(p.title)", start: start, allDay: !step.hasTime, done: step.done,
                                      sourceURL: p.fileURL))
            }
        }
        return out
    }
}
