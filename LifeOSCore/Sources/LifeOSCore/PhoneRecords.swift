import Foundation

// 手机版写进 vault 的三类记录：专注（`健康/专注/YYYY-MM-DD.md`，手机独有）、
// 一次训练（`健康/训练记录/` 里新建一个文件）、睡眠（`健康/睡眠/YYYY-MM.md`，只补没记过的那天，不替换）。
// 电脑版和 agent 对专注文件只读；训练记录文件建好以后手机不再改它。

// MARK: - 安全写入

public enum SafeFileWrite {
    public enum WriteError: Error, LocalizedError {
        case replaceFailed(Int32)
        public var errorDescription: String? {
            switch self { case .replaceFailed(let e): "替换文件失败（\(String(cString: strerror(e)))）" }
        }
    }

    /// 读 → 改 → 原子换掉：在 NSFileCoordinator 里从磁盘重读（不存在时 `transform` 拿到 nil），
    /// `transform` 返回 nil 表示不写。新内容先写到 `scratch`（App 自己的临时目录），再 rename(2) 换掉 / 放到目标位置。
    /// 目标文件夹不存在就建。返回是否写了。
    @discardableResult
    public static func update(_ url: URL, scratch: URL = FileManager.default.temporaryDirectory,
                              _ transform: (String?) throws -> String?) throws -> Bool {
        var result: Result<Bool, Error> = .success(false)
        var coordError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { target in
            result = Result {
                let fm = FileManager.default
                let before = try? String(contentsOf: target, encoding: .utf8)
                guard let after = try transform(before), after != before else { return false }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
                let tmp = scratch.appendingPathComponent("lifeos-\(UUID().uuidString).md")
                defer { try? fm.removeItem(at: tmp) }
                try Data(after.utf8).write(to: tmp)
                if let perm = try? fm.attributesOfItem(atPath: target.path)[.posixPermissions] {
                    try? fm.setAttributes([.posixPermissions: perm], ofItemAtPath: tmp.path)
                }
                let rc = tmp.withUnsafeFileSystemRepresentation { src in
                    target.withUnsafeFileSystemRepresentation { dst in rename(src!, dst!) }
                }
                guard rc == 0 else { throw WriteError.replaceFailed(errno) }
                return true
            }
        }
        if let coordError { throw coordError }
        return try result.get()
    }
}

// MARK: - 专注

/// 一段专注：`健康/专注/YYYY-MM-DD.md` 表里的一行
public struct FocusSession: Equatable, Sendable, Identifiable {
    public var id: String { "\(DateText.format(start, withTime: true))-\(label)" }
    public var start: Date
    public var end: Date
    /// 实际专注的分钟（不含中途离开的时间）
    public var minutes: Double
    /// 做什么（事项标题或自己写的）
    public var label: String
    /// 中途切到别的 App 几次、一共多久（锁屏不算离开）
    public var leaves: Int
    public var leaveMinutes: Double
    public var note: String

    public init(start: Date, end: Date, minutes: Double, label: String, leaves: Int = 0, leaveMinutes: Double = 0, note: String = "") {
        self.start = start
        self.end = end
        self.minutes = minutes
        self.label = label
        self.leaves = leaves
        self.leaveMinutes = leaveMinutes
        self.note = note
    }
}

public struct FocusStore: Sendable {
    public let dir: URL

    public init(vault: URL) { dir = vault.appendingPathComponent("健康").appendingPathComponent("专注") }

    public func url(_ day: Date, calendar: Calendar = .current) -> URL {
        dir.appendingPathComponent("\(DateText.format(day, withTime: false, calendar: calendar)).md")
    }

    static let header = "| 开始 | 结束 | 分钟 | 做什么 | 离开 | 备注 |\n|---|---|---|---|---|---|"

    /// 所有记录，旧的在前
    public func load(calendar: Calendar = .current) -> [FocusSession] {
        HealthStore.markdownFiles(in: dir).flatMap { url -> [FocusSession] in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return Self.parse(text, calendar: calendar)
        }.sorted { $0.start < $1.start }
    }

    /// 日期取 frontmatter 的 `date`；开始、结束只写时刻，结束早于开始算跨了午夜
    static func parse(_ text: String, calendar: Calendar) -> [FocusSession] {
        let doc = Frontmatter.parse(text)
        guard let dayText = doc.fields["date"], let day = DateText.parse(dayText, calendar: calendar),
              let t = MarkdownTable.tables(in: doc.body).first(where: { $0.header.contains { $0.contains("分钟") } }) else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        return t.rows.compactMap { row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let s = HealthStore.clockMinutes(cell(idx("开始"))) else { return nil }
            let start = day.addingTimeInterval(s * 60)
            var end = HealthStore.clockMinutes(cell(idx("结束"))).map { day.addingTimeInterval($0 * 60) } ?? start
            if end < start { end = end.addingTimeInterval(86400) }
            let minutes = HealthStore.number(cell(idx("分钟"))) ?? end.timeIntervalSince(start) / 60
            let leave = cell(idx("离开"))
            let nums = leave.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).compactMap(Double.init)
            return FocusSession(start: start, end: end, minutes: minutes, label: cell(idx("做什么")),
                                leaves: nums.first.map { Int($0) } ?? 0, leaveMinutes: nums.count > 1 ? nums[1] : 0,
                                note: cell(idx("备注")))
        }
    }

    static func row(_ s: FocusSession, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        let leave = s.leaves == 0 ? "" : "\(s.leaves) 次 / \(Int(s.leaveMinutes.rounded())) 分钟"
        func clean(_ t: String) -> String {
            t.replacingOccurrences(of: "|", with: "／").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        return "| \(f.string(from: s.start)) | \(f.string(from: s.end)) | \(Int(s.minutes.rounded())) | \(clean(s.label)) | \(leave) | \(clean(s.note)) |"
    }

    /// 在开始那天的文件末尾追加一行；没有文件就新建
    public func append(_ s: FocusSession, calendar: Calendar = .current,
                       scratch: URL = FileManager.default.temporaryDirectory) throws {
        let day = DateText.format(s.start, withTime: false, calendar: calendar)
        let row = Self.row(s, calendar: calendar)
        try SafeFileWrite.update(url(s.start, calendar: calendar), scratch: scratch) { before in
            guard var text = before else {
                return "---\ntype: health-focus\ndate: \(day)\n---\n# \(day) 专注\n\n\(Self.header)\n\(row)\n"
            }
            guard text.contains("| 分钟 |") else { return text + (text.hasSuffix("\n") ? "" : "\n") + "\n\(Self.header)\n\(row)\n" }
            // 表格是文件里最后一块：去掉末尾空行再接一行
            while text.hasSuffix("\n") { text.removeLast() }
            return text + "\n" + row + "\n"
        }
    }
}

public enum FocusSummary {
    /// 某天一共专注了多少分钟
    public static func minutes(on day: Date, in sessions: [FocusSession], calendar: Calendar) -> Double {
        sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.minutes }
    }

    /// 某天按“做什么”分组的分钟，多的在前
    public static func byLabel(on day: Date, in sessions: [FocusSession], calendar: Calendar) -> [(label: String, minutes: Double)] {
        let today = sessions.filter { calendar.isDate($0.start, inSameDayAs: day) }
        return Dictionary(grouping: today) { $0.label.isEmpty ? "没写" : $0.label }
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.1 > $1.1 }
    }
}

// MARK: - 训练

/// 手机上做完的一组
public struct LoggedSet: Equatable, Sendable, Codable {
    public var exercise: String
    /// 重量（单位见动作的 unit）；自重、计时为 nil
    public var weight: Double?
    /// 次数；计时动作是秒
    public var reps: Double
    /// 这组之后实际休息了多少秒（最后一组没有）
    public var rest: Double?

    public init(exercise: String, weight: Double?, reps: Double, rest: Double? = nil) {
        self.exercise = exercise
        self.weight = weight
        self.reps = reps
        self.rest = rest
    }
}

public enum WorkoutLog {
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    /// 表格行：同一动作、相邻、重量和次数都一样的组合成一行（`2×9`），和 agent 手写的训练记录一样
    public static func rows(_ sets: [LoggedSet]) -> [String] {
        var out: [(LoggedSet, Int)] = []
        for s in sets {
            if let last = out.last, last.0.exercise == s.exercise, last.0.weight == s.weight, last.0.reps == s.reps {
                out[out.count - 1].1 += 1
            } else {
                out.append((s, 1))
            }
        }
        return out.map { s, n in "| \(s.exercise) | \(s.weight.map(fmt) ?? "自重") | \(n)×\(fmt(s.reps)) |" }
    }

    public static func markdown(title: String, date: Date, start: Date, end: Date, sets: [LoggedSet],
                                note: String, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
        let rests = sets.compactMap(\.rest)
        var lines = [
            "---", "type: health-session", "date: \(DateText.format(date, withTime: false, calendar: calendar))",
            "kind: strength", "title: \(title)", "duration: \(minutes):00", "source: phone", "---",
            "手机记的：\(f.string(from: start))–\(f.string(from: end))，\(minutes) 分钟，\(sets.count) 组。", "",
            "| 动作 | 重量 | 组×次 |", "|---|---|---|",
        ]
        lines += rows(sets)
        lines.append("")
        if !rests.isEmpty {
            let avg = rests.reduce(0, +) / Double(rests.count)
            lines.append("- 组间平均休息 \(Int(avg.rounded())) 秒。")
        }
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { lines.append("- \(n)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension HealthStore {
    /// 新建一次训练记录（`训练记录/YYYY-MM-DD 标题.md`，重名加 ` 2`），不覆盖已有文件。返回新文件
    @discardableResult
    public func writeSession(title: String, fileTitle: String, date: Date, start: Date, end: Date, sets: [LoggedSet],
                             note: String, calendar: Calendar = .current,
                             scratch: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let day = DateText.format(date, withTime: false, calendar: calendar)
        let safe = fileTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let text = WorkoutLog.markdown(title: title, date: date, start: start, end: end, sets: sets, note: note, calendar: calendar)
        for n in 1...50 {
            let url = sessionsDir.appendingPathComponent("\(day) \(safe)\(n == 1 ? "" : " \(n)").md")
            if FileManager.default.fileExists(atPath: url.path) { continue }
            // 写的那一刻再确认一次不存在（同步可能刚带来同名文件）
            if try SafeFileWrite.update(url, scratch: scratch, { $0 == nil ? text : nil }) { return url }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}

extension Exercise {
    /// 这次建议用的重量：上次做满目标就加一档，没做满就和上次一样；没有记录时 nil
    public var suggestedWeight: Double? {
        guard let last = records.last, let w = last.weight else { return nil }
        guard let goal = targetSetsReps, let step else { return w }
        let full = (last.sets ?? goal.sets) >= goal.sets && (last.reps ?? 0) >= goal.reps
        return full ? w + step : w
    }

    /// 默认组间休息（秒）：多关节大重量动作 150，计时 / 核心 60，其他 90
    public var defaultRest: Double {
        if kind == .timed { return 60 }
        let big: Set<String> = ["chest", "quadriceps", "hamstring", "gluteal", "upper-back", "lower-back", "trapezius"]
        if kind == .strength, primary.contains(where: big.contains) { return 150 }
        if primary.contains("abs") || primary.contains("obliques") { return 60 }
        return 90
    }
}

// MARK: - 睡眠：从用手机的时间推算

/// 手机“最后一次用 → 第一次用”推一晚睡眠。事件来自 LifeOS 自己进出前台、锁屏 / 解锁，
/// 以及用户在“快捷指令”里设的自动化（打开 / 关闭常用 App 时运行“记一下用了手机”）。
public enum SleepInference {
    /// 至少空这么久才算睡了
    public static let minSleep: TimeInterval = 3 * 3600
    /// 两段空档中间用手机不超过这么久（半夜看一眼时间、上厕所），合成一晚
    public static let maxWakeGap: TimeInterval = 20 * 60
    /// 最长一晚（更长多半是手机没用而不是在睡）
    public static let maxSleep: TimeInterval = 14 * 3600

    /// 在 `now` 推算刚过去的这一晚：取前一天 18:00 到 now 之间最长的空档（≥ 3 小时、和 0–6 点有重叠），
    /// 再把它前后只隔了一小会儿的空档并进来（往前的要也在半夜，往后的要在上午 11 点前结束）。now 早于 5 点不推（可能半夜醒了还要接着睡）。
    public static func lastNight(events: [Date], now: Date, calendar: Calendar) -> (bed: Date, wake: Date)? {
        guard calendar.component(.hour, from: now) >= 5,
              let today = Optional(calendar.startOfDay(for: now)),
              let from = calendar.date(byAdding: .hour, value: -6, to: today),
              let nightEnd = calendar.date(byAdding: .hour, value: 6, to: today) else { return nil }
        let ev = (events.filter { $0 >= from && $0 <= now } + [now]).sorted()
        guard ev.count >= 2 else { return nil }
        // 相邻两次之间的空档
        var gaps: [(Date, Date)] = []
        for i in 1..<ev.count where ev[i].timeIntervalSince(ev[i - 1]) >= 30 * 60 {
            gaps.append((ev[i - 1], ev[i]))
        }
        let night = gaps.indices.filter { gaps[$0].0 < nightEnd && gaps[$0].1 > today }
        guard let best = night.max(by: { gaps[$0].1.timeIntervalSince(gaps[$0].0) < gaps[$1].1.timeIntervalSince(gaps[$1].0) }),
              gaps[best].1.timeIntervalSince(gaps[best].0) >= minSleep else { return nil }
        var lo = best, hi = best
        // 往前只并半夜里的空档（晚上放下手机学习那段不算睡），往后醒来看一眼又睡的都并
        while lo > 0, gaps[lo].0.timeIntervalSince(gaps[lo - 1].1) <= maxWakeGap, night.contains(lo - 1) { lo -= 1 }
        // 往后的要在上午 11 点前结束（早上醒了看一眼又睡；白天上课没碰手机不算）
        let lateMorning = nightEnd.addingTimeInterval(5 * 3600)
        while hi < gaps.count - 1, gaps[hi + 1].0.timeIntervalSince(gaps[hi].1) <= maxWakeGap, gaps[hi + 1].1 <= lateMorning { hi += 1 }
        let bed = gaps[lo].0, wake = gaps[hi].1
        guard wake.timeIntervalSince(bed) <= maxSleep else { return nil }
        return (bed, wake)
    }
}

extension HealthStore {
    /// 自动推算的一晚：起床那天还没有记录才写（手动记的、电脑上改过的都不动），按日期插进去。返回是否写了
    @discardableResult
    public func addInferredSleep(bed: Date, wake: Date, calendar: Calendar = .current,
                                 scratch: URL = FileManager.default.temporaryDirectory) throws -> Bool {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        let day = DateText.format(wake, withTime: false, calendar: calendar)
        let total = Int((wake.timeIntervalSince(bed) / 60).rounded())
        let row = "| \(day) | \(f.string(from: bed)) | \(f.string(from: wake)) | \(total / 60):\(String(format: "%02d", total % 60)) |"
        return try SafeFileWrite.update(sleepURL(wake, calendar: calendar), scratch: scratch) { before in
            guard let before else {
                let month = day.prefix(7)
                return "---\ntype: health-sleep\nmonth: \(month)\n---\n# \(month) 睡眠\n\n\(Self.sleepHeader)\n\(row)\n"
            }
            if Self.parseSleep(before, calendar: calendar).contains(where: { DateText.format($0.date, withTime: false, calendar: calendar) == day }) {
                return nil
            }
            return Self.upsertSleepRow(row, day: day, into: before)
        }
    }
}
