import Foundation

/// 从 CourseOS 学期目录**只读**取出日历要用的东西：上课时间、截止/考试、长期项目子任务。
/// 永远不写 CourseOS 的任何文件。
public struct CourseOSSnapshot: Sendable, Equatable {
    public struct Course: Sendable, Equatable {
        public var id: String
        public var directory: String
        public var schedule: String
        public var location: String
    }

    public struct Entry: Sendable, Equatable {
        public var id: String
        public var course: String
        public var title: String
        public var kind: String
        public var when: Date
        public var hasTime: Bool
        public var category: String
        public var workloadHours: Double?
        public var gradeWeight: Double?
        public var done: Bool
        public var ignored: Bool
        public var sourceURL: URL?
    }

    public struct Subtask: Sendable, Equatable {
        public var id: String
        public var projectTitle: String
        public var course: String
        public var title: String
        public var due: Date
        public var hasTime: Bool
        public var done: Bool
        public var estimateHours: Double?
    }

    public var semesterRoot: URL
    public var courses: [Course]
    public var entries: [Entry]
    public var subtasks: [Subtask]

    public static let empty = CourseOSSnapshot(semesterRoot: URL(fileURLWithPath: "/"), courses: [], entries: [], subtasks: [])
}

public enum CourseOSBridge {
    public enum BridgeError: Error, Equatable { case notASemester(String) }

    /// 读取学期目录。courseos.json 都没有时抛错（路径设错了）；其余文件缺失就当没有。
    public static func load(semester: URL, calendar: Calendar = .current) throws -> CourseOSSnapshot {
        let configURL = semester.appendingPathComponent("courseos.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.notASemester(semester.path)
        }
        var courses: [CourseOSSnapshot.Course] = []
        for c in json["courses"] as? [[String: Any]] ?? [] {
            guard let id = c["id"] as? String, (c["enabled"] as? Bool) ?? true else { continue }
            let manual = c["profile"] as? [String: Any] ?? [:]
            let extracted = profile(semester: semester, course: id)
            func pick(_ key: String) -> String {
                let m = (manual[key] as? String) ?? ""
                return m.isEmpty ? ((extracted[key] as? String) ?? "") : m
            }
            courses.append(.init(id: id, directory: c["directory"] as? String ?? id,
                                 schedule: pick("schedule"), location: pick("location")))
        }
        let known = Set(courses.map(\.id))
        let tableURL = semester.appendingPathComponent("_exports/planvault-time-sensitive.md")
        let entries = ((try? String(contentsOf: tableURL, encoding: .utf8)).map { parseTable($0, calendar: calendar) } ?? [])
            .filter { known.isEmpty || known.contains($0.course) }
        return CourseOSSnapshot(semesterRoot: semester, courses: courses, entries: entries,
                                subtasks: projects(semester: semester, calendar: calendar))
    }

    static func profile(semester: URL, course: String) -> [String: Any] {
        let url = semester.appendingPathComponent(".courseos/profiles/\(course).json")
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// 追踪中的长期项目里、带日期的子任务
    static func projects(semester: URL, calendar: Calendar) -> [CourseOSSnapshot.Subtask] {
        let dir = semester.appendingPathComponent(".courseos/projects")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        var result: [CourseOSSnapshot.Subtask] = []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let p = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (p["state"] as? String) == "tracked" else { continue }
            let pid = p["id"] as? String ?? file.deletingPathExtension().lastPathComponent
            for s in p["subtasks"] as? [[String: Any]] ?? [] {
                guard let dueText = s["due"] as? String, let due = DateText.parse(dueText, calendar: calendar) else { continue }
                result.append(.init(id: "\(pid)/\(s["id"] as? String ?? UUID().uuidString)",
                                    projectTitle: p["title"] as? String ?? pid,
                                    course: p["course"] as? String ?? "",
                                    title: s["title"] as? String ?? "",
                                    due: due, hasTime: DateText.hasTime(dueText),
                                    done: s["done"] as? Bool ?? false,
                                    estimateHours: (s["estimateHours"] as? NSNumber)?.doubleValue))
            }
        }
        return result
    }

    /// 解析待办表（按表头名找列；`\|` 是转义的竖线）
    public static func parseTable(_ text: String, calendar: Calendar = .current) -> [CourseOSSnapshot.Entry] {
        var header: [String] = []
        var result: [CourseOSSnapshot.Entry] = []
        for line in text.components(separatedBy: "\n") {
            guard let cells = splitRow(line) else { continue }
            if cells.first == "id" { header = cells; continue }
            guard !header.isEmpty, cells.count == header.count else { continue }
            func cell(_ name: String) -> String { header.firstIndex(of: name).map { cells[$0] } ?? "" }
            let whenText = cell("when")
            guard let when = DateText.parse(whenText, calendar: calendar) else { continue }
            let status = cell("status").lowercased()
            let url = cell("source_url")
            result.append(.init(
                id: cell("id"), course: cell("course"), title: cell("title"), kind: cell("event_kind"),
                when: when, hasTime: DateText.hasTime(whenText), category: cell("category").lowercased(),
                workloadHours: Hours.parse(cell("estimated_workload")),
                gradeWeight: Double(cell("grade_weight").replacingOccurrences(of: "%", with: "")),
                done: status == "done" || ["true", "yes"].contains(cell("submitted").lowercased()),
                ignored: status == "ignored",
                sourceURL: url.isEmpty ? nil : URL(string: url)))
        }
        return result
    }

    static func splitRow(_ line: String) -> [String]? {
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > 2, t.hasPrefix("|"), t.hasSuffix("|") else { return nil }
        var cells: [String] = []
        var current = ""
        var prev: Character?
        for ch in t.dropFirst() {
            if ch == "|", prev != "\\" {
                cells.append(current.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|"))
                current = ""
            } else {
                current.append(ch)
            }
            prev = ch
        }
        return cells
    }

    // MARK: - 转成日历上的出现

    /// 课程图层在某段时间内的所有出现。classesFrom/Until 限定上课块的范围。
    public static func occurrences(_ snap: CourseOSSnapshot, in range: DateInterval, config: LifeConfig,
                                   calendar: Calendar = .current) -> [Occurrence] {
        var result: [Occurrence] = []
        let layers = config.layers
        if layers.classes {
            let from = config.courseos.classesFrom.flatMap { DateText.parse($0, calendar: calendar) } ?? .distantPast
            let until = config.courseos.classesUntil.flatMap { DateText.parse($0, calendar: calendar) }
                .map { Recurrence.endOfDay($0, calendar) } ?? .distantFuture
            for course in snap.courses {
                let meetings = ClassSchedule.meetings(course.schedule, section: config.courseos.sections[course.id])
                guard !meetings.isEmpty else { continue }
                var day = calendar.startOfDay(for: max(range.start, from))
                while day < range.end, day <= until {
                    let weekday = calendar.component(.weekday, from: day)
                    for m in meetings where m.weekdays.contains(weekday) {
                        // 用“设定时分”而不是加秒数：夏令时切换那天也对
                        guard let s = calendar.date(bySettingHour: m.startMinute / 60, minute: m.startMinute % 60, second: 0, of: day),
                              let e = calendar.date(bySettingHour: m.endMinute / 60, minute: m.endMinute % 60, second: 0, of: day)
                        else { continue }
                        result.append(Occurrence(
                            id: "class:\(course.id)@\(DateText.format(s, withTime: true, calendar: calendar))",
                            style: .classSession, title: course.id, subtitle: course.location,
                            start: s, end: e, course: course.id, location: course.location))
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
        }
        for e in snap.entries where !e.ignored && range.contains(e.when) {
            let style: Occurrence.Style
            if e.kind == "exam" { style = .courseExam }
            else if e.category == "optional" || e.category == "notice" { style = .courseOptional }
            else { style = .courseDue }
            if style == .courseOptional && !layers.courseOptional { continue }
            if style != .courseOptional && !layers.courseDeadlines { continue }
            result.append(Occurrence(
                id: "course:\(e.id)", style: style, title: e.title, subtitle: e.course,
                start: e.when, end: nil, allDay: !e.hasTime, done: e.done,
                courseItemID: e.id, course: e.course, workloadHours: e.workloadHours, sourceURL: e.sourceURL))
        }
        if layers.courseDeadlines {
            for s in snap.subtasks where range.contains(s.due) {
                result.append(Occurrence(
                    id: "project:\(s.id)", style: .courseDue, title: s.title, subtitle: "\(s.course) · \(s.projectTitle)",
                    start: s.due, end: nil, allDay: !s.hasTime, done: s.done,
                    courseItemID: s.id, course: s.course, workloadHours: s.estimateHours))
            }
        }
        return result
    }
}
