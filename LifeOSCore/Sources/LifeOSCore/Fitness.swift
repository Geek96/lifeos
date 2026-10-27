import Foundation

// 健身：`健康/动作/` 每个动作一个文件（练哪块肌肉、目标组次、每次的记录），`健康/训练计划.md` 是学期里的一周计划表。
// agent 写；App 只读。

/// 肌肉分布图上的一块肌肉（键名和 BodyMapData 一致）
public struct Muscle: Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let zh: String
    public let en: String

    /// 图上能点的肌肉（head、knees 不算），按从上到下、先前后后排
    public static let all: [Muscle] = [
        .init(key: "neck", zh: "颈部", en: "Neck"),
        .init(key: "trapezius", zh: "斜方肌", en: "Trapezius"),
        .init(key: "front-deltoids", zh: "三角肌前束", en: "Front delts"),
        .init(key: "back-deltoids", zh: "三角肌后束", en: "Rear delts"),
        .init(key: "chest", zh: "胸大肌", en: "Chest"),
        .init(key: "upper-back", zh: "背阔肌", en: "Lats"),
        .init(key: "biceps", zh: "肱二头肌", en: "Biceps"),
        .init(key: "triceps", zh: "肱三头肌", en: "Triceps"),
        .init(key: "forearm", zh: "前臂", en: "Forearms"),
        .init(key: "abs", zh: "腹直肌", en: "Abs"),
        .init(key: "obliques", zh: "腹斜肌", en: "Obliques"),
        .init(key: "lower-back", zh: "竖脊肌", en: "Lower back"),
        .init(key: "gluteal", zh: "臀大肌", en: "Glutes"),
        .init(key: "abductors", zh: "髋外展肌", en: "Abductors"),
        .init(key: "adductor", zh: "大腿内收肌", en: "Adductors"),
        .init(key: "quadriceps", zh: "股四头肌", en: "Quadriceps"),
        .init(key: "hamstring", zh: "腘绳肌", en: "Hamstrings"),
        .init(key: "calves", zh: "小腿", en: "Calves"),
    ]

    public static func named(_ key: String) -> Muscle? { all.first { $0.key == key } }
}

/// 一次记录：一行 `| 日期 | 重量 | 次数 | 组数 | 备注 |`
public struct ExerciseRecord: Equatable, Sendable, Identifiable {
    public var id: Int
    public var date: Date
    /// 重量（单位见动作的 unit）；自重动作为 nil
    public var weight: Double?
    /// 每组做到的次数（几组里最少的那组）；计时的动作是秒
    public var reps: Double?
    public var repsText: String
    public var sets: Int?
    public var note: String

    /// 估算 1RM（Epley：重量 × (1 + 次数 / 30)），只在有重量、次数时有
    public var estimated1RM: Double? {
        guard let w = weight, let r = reps, r > 0 else { return nil }
        return r == 1 ? w : w * (1 + r / 30)
    }
}

/// 一周里最好的一次
public struct WeeklyBest: Equatable, Sendable, Identifiable {
    public var id: Date { weekStart }
    public var weekStart: Date
    public var record: ExerciseRecord
}

public struct Exercise: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case strength, bodyweight, timed, cardio }

    public var id: String { fileURL.path }
    public var fileURL: URL
    public var name: String
    public var nameEn: String
    public var kind: Kind
    /// 主要练到的肌肉（键名）
    public var primary: [String]
    /// 辅助参与的肌肉
    public var secondary: [String]
    /// 安排在哪天（“周一 背”）
    public var day: String
    public var equipment: String
    public var unit: String
    /// 目标组次（“3×10”“3×30 秒”）
    public var target: String
    /// 每次加多少（只写数字，单位同 unit）
    public var step: Double?
    public var source: String
    public var body: String
    /// 按日期从旧到新
    public var records: [ExerciseRecord]

    public func section(_ name: String) -> String { Trip.section(name, in: body) }

    /// “3×10”→(3, 10)；“2×每条腿 10 个”→(2, 10)；“3×30 秒”→(3, 30)
    public var targetSetsReps: (sets: Int, reps: Double)? {
        let parts = target.replacingOccurrences(of: "x", with: "×").replacingOccurrences(of: "X", with: "×")
            .components(separatedBy: "×")
        guard parts.count == 2, let s = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let r = HealthStore.number(parts[1]) else { return nil }
        return (s, r)
    }

    /// 每周最好的一次：有重量的比重量（同重量比次数），自重和计时的比次数 / 秒
    public func weeklyBests(calendar: Calendar) -> [WeeklyBest] {
        let byWeek = Dictionary(grouping: records) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return byWeek.compactMap { week, recs in
            recs.max { a, b in
                ((a.weight ?? 0), (a.reps ?? 0)) < ((b.weight ?? 0), (b.reps ?? 0))
            }.map { WeeklyBest(weekStart: week, record: $0) }
        }.sorted { $0.weekStart < $1.weekStart }
    }

    /// 下一次怎么练：最近一次做满目标组次就加量，没做满就保持（双重递进）
    public var nextHint: String? {
        guard let last = records.last else {
            return target.isEmpty ? nil : "还没有记录。先按 \(target) 做，记下用的重量和每组做到几个。"
        }
        guard let goal = targetSetsReps else { return nil }
        let setsDone = last.sets ?? goal.sets
        let full = setsDone >= goal.sets && (last.reps ?? 0) >= goal.reps
        let repsUnit = kind == .timed ? " 秒" : " 个"
        switch kind {
        case .strength:
            guard let w = last.weight else { return nil }
            if full, let step {
                return "上次 \(fmt(w)) \(unit) 做满了 \(goal.sets)×\(fmt(goal.reps))。下次试 \(fmt(w + step)) \(unit)。"
            }
            return "上次 \(fmt(w)) \(unit)，每组做到 \(last.repsText)。下次保持 \(fmt(w)) \(unit)，争取每组做满 \(fmt(goal.reps))\(repsUnit)。"
        case .bodyweight, .timed:
            if full {
                let more = kind == .timed ? 10.0 : 2.0
                return "上次做满了 \(goal.sets)×\(fmt(goal.reps))\(repsUnit)。下次每组试 \(fmt((last.reps ?? goal.reps) + more))\(repsUnit)。"
            }
            return "上次每组做到 \(last.repsText)。下次争取每组做满 \(fmt(goal.reps))\(repsUnit)。"
        case .cardio:
            return nil
        }
    }

    private func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    static func parse(text: String, fileURL: URL, calendar: Calendar) -> Exercise? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "exercise" else { return nil }
        let body = doc.body
        return Exercise(fileURL: fileURL, name: f["name"] ?? fileURL.deletingPathExtension().lastPathComponent,
                        nameEn: f["name_en"] ?? "", kind: Kind(rawValue: f["kind"] ?? "") ?? .strength,
                        primary: Tags.split(f["primary"] ?? ""), secondary: Tags.split(f["secondary"] ?? ""),
                        day: f["day"] ?? "", equipment: f["equipment"] ?? "", unit: f["unit"] ?? "lb",
                        target: f["target"] ?? "", step: f["step"].flatMap(HealthStore.number), source: f["source"] ?? "",
                        body: body, records: parseRecords(Trip.section("记录", in: body), calendar: calendar))
    }

    /// | 日期 | 重量 | 次数 | 组数 | 备注 |
    static func parseRecords(_ text: String, calendar: Calendar) -> [ExerciseRecord] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        return t.rows.enumerated().compactMap { i, row -> ExerciseRecord? in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            guard let d = DateText.parse(cell(idx("日期") ?? 0), calendar: calendar) else { return nil }
            let reps = cell(idx("次数"))
            return ExerciseRecord(id: i, date: d, weight: HealthStore.number(cell(idx("重量"))), reps: HealthStore.number(reps),
                                  repsText: reps, sets: HealthStore.number(cell(idx("组数"))).map { Int($0) }, note: cell(idx("备注")))
        }.sorted { $0.date < $1.date }
    }
}

/// `健康/训练计划.md` 的“学期一周”表：| 星期 | 时间 | 内容 | 动作 |
public struct WeekPlan: Equatable, Sendable {
    public struct Day: Equatable, Sendable, Identifiable {
        public var id: String { weekday }
        public var weekday: String
        public var time: String
        public var what: String
        /// 动作名（“、”分隔拆开）
        public var exercises: [String]
    }

    public var days: [Day]
    public var notes: String

    public static let empty = WeekPlan(days: [], notes: "")

    static func parse(_ text: String) -> WeekPlan {
        let body = Frontmatter.parse(text).body
        let section = Trip.section("学期一周", in: body)
        guard let t = MarkdownTable.tables(in: section).first else { return .empty }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        let days = t.rows.compactMap { row -> Day? in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let wd = cell(idx("星期") ?? 0)
            guard !wd.isEmpty else { return nil }
            return Day(weekday: wd, time: cell(idx("时间")), what: cell(idx("内容")), exercises: Tags.split(cell(idx("动作"))))
        }
        // 表格下面的说明（列表项）
        let notes = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.joined(separator: "\n")
        return WeekPlan(days: days, notes: notes)
    }

    /// 周一 = 1 … 周日 = 7，对应 Calendar 的 weekday（周日 = 1）
    public static func index(of weekday: String) -> Int? {
        let names = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        return names.firstIndex { weekday.hasPrefix($0) }.map { $0 + 1 }
    }
}

extension HealthStore {
    public var exercisesDir: URL { root.appendingPathComponent("动作") }
    public var planURL: URL { root.appendingPathComponent("训练计划.md") }

    public func loadExercises(calendar: Calendar = .current) -> [Exercise] {
        Self.markdownFiles(in: exercisesDir).compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).flatMap { Exercise.parse(text: $0, fileURL: url, calendar: calendar) }
        }
    }

    public func loadWeekPlan() -> WeekPlan {
        (try? String(contentsOf: planURL, encoding: .utf8)).map(WeekPlan.parse) ?? .empty
    }
}

/// 每块肌肉被哪些动作练到
public enum MuscleCoverage {
    public struct Entry: Sendable {
        public var primary: [Exercise]
        public var secondary: [Exercise]
        public var trained: Bool { !primary.isEmpty || !secondary.isEmpty }
    }

    public static func compute(_ exercises: [Exercise]) -> [String: Entry] {
        var out: [String: Entry] = [:]
        for m in Muscle.all {
            out[m.key] = Entry(primary: exercises.filter { $0.primary.contains(m.key) },
                               secondary: exercises.filter { $0.secondary.contains(m.key) && !$0.primary.contains(m.key) })
        }
        return out
    }
}
