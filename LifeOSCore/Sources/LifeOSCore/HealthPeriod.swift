import Foundation

// 健康三页（营养 / 健身与锻炼 / 休息与放松）共用的“日 / 周 / 月”尺度，和每个尺度下的汇总。
// 只陈述数字，不打分。

/// 正在看的一段时间：某一天、某一周（按日历的周起始日）、某个月
public struct HealthPeriod: Equatable, Sendable {
    public enum Scale: String, CaseIterable, Sendable {
        case day, week, month
        public var label: String {
            switch self { case .day: "日"; case .week: "周"; case .month: "月" }
        }
        var component: Calendar.Component {
            switch self { case .day: .day; case .week: .weekOfYear; case .month: .month }
        }
    }

    public var scale: Scale
    /// 落在这段时间里的任意一天
    public var anchor: Date

    public init(scale: Scale, anchor: Date) {
        self.scale = scale
        self.anchor = anchor
    }

    public func interval(calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: scale.component, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 86400)
    }

    /// 这段时间里每一天的 0 点
    public func days(calendar: Calendar) -> [Date] {
        let iv = interval(calendar: calendar)
        var out: [Date] = []
        var d = iv.start
        while d < iv.end {
            out.append(d)
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    /// 往前 / 往后翻 n 段
    public func stepped(_ n: Int, calendar: Calendar) -> HealthPeriod {
        HealthPeriod(scale: scale, anchor: calendar.date(byAdding: scale.component, value: n, to: anchor) ?? anchor)
    }

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        interval(calendar: calendar).containsHalfOpen(date)
    }
}

extension DateInterval {
    /// 含开始、不含结束（系统的 contains 两头都含：下周一 0 点会被算进这周）
    public func containsHalfOpen(_ date: Date) -> Bool { date >= start && date < end }
}

// MARK: - 营养

/// 一段时间的饮食汇总：平均只用记全了的日子，目标按每天当时的目标平均
public struct NutritionSummary: Equatable, Sendable {
    /// 有记录的天数（包括只记了一半的）
    public var loggedDays: Int
    /// 记全的那几天
    public var completeDays: [DietDay]
    /// 只记了一部分的天数（`complete: false`）
    public var partialDays: Int
    public var average: Nutrition?
    public var averageTarget: Nutrition?
}

extension HealthSnapshot {
    public func nutritionSummary(_ days: [Date], today: Date, calendar: Calendar) -> NutritionSummary {
        let diets = days.map { day($0, calendar: calendar) }
        let complete = diets.filter { $0.isComplete(today: today, calendar: calendar) }
        return NutritionSummary(
            loggedDays: diets.filter { !$0.meals.isEmpty }.count,
            completeDays: complete,
            partialDays: diets.filter { $0.complete == false }.count,
            average: Nutrition.average(complete.map(\.total)),
            averageTarget: Nutrition.average(complete.compactMap { targets(on: $0.date, calendar: calendar) }))
    }
}

extension Nutrition {
    /// 平均；空就是 nil。微量营养按每项各自出现的次数平均
    public static func average(_ values: [Nutrition]) -> Nutrition? {
        guard !values.isEmpty else { return nil }
        let n = Double(values.count)
        let sum = values.reduce(.zero, +)
        var counts: [String: Double] = [:]
        for v in values { for k in v.micros.keys { counts[k, default: 0] += 1 } }
        return Nutrition(kcal: sum.kcal / n, protein: sum.protein / n, carbs: sum.carbs / n, fat: sum.fat / n,
                         micros: sum.micros.reduce(into: [:]) { $0[$1.key] = $1.value / (counts[$1.key] ?? n) })
    }
}

// MARK: - 健身与锻炼

/// 一段时间的训练汇总
public struct FitnessSummary: Equatable, Sendable {
    public var sessions: [HealthSession]
    /// 练了的天数（一天练两次算一天）
    public var activeDays: Int
    public var strengthCount: Int
    public var runCount: Int
    public var runKm: Double
    public var volume: Double
    /// 有距离也有用时的跑步的平均配速（分钟 / 公里）
    public var pace: Double?
}

extension HealthSnapshot {
    public func fitnessSummary(in interval: DateInterval, calendar: Calendar) -> FitnessSummary {
        let inside = sessions.filter { interval.containsHalfOpen($0.date) }.sorted { $0.date < $1.date }
        let runs = inside.filter { $0.kind == .run }
        let timed = runs.filter { $0.distanceKm != nil && $0.minutes != nil }
        let timedKm = timed.compactMap(\.distanceKm).reduce(0, +)
        return FitnessSummary(
            sessions: inside,
            activeDays: Set(inside.map { calendar.startOfDay(for: $0.date) }).count,
            strengthCount: inside.filter { $0.kind == .strength }.count,
            runCount: runs.count,
            runKm: runs.compactMap(\.distanceKm).reduce(0, +),
            volume: inside.compactMap(\.volume).reduce(0, +),
            pace: timedKm > 0 ? timed.compactMap(\.minutes).reduce(0, +) / timedKm : nil)
    }
}

// MARK: - 休息与放松

/// 一段时间的睡眠汇总
public struct SleepSummary: Equatable, Sendable {
    public var nights: [SleepNight]
    public var averageMinutes: Double?
    /// 平均几点睡（“00:40”）：按晚上 12 点前后连着算，不会把 23:30 和 00:30 平均成中午
    public var averageBedtime: String?
    public var averageWake: String?
}

extension HealthSnapshot {
    public func sleepSummary(in interval: DateInterval) -> SleepSummary {
        let inside = sleep.filter { interval.containsHalfOpen($0.date) }
        let mins = inside.compactMap(\.minutes)
        return SleepSummary(
            nights: inside,
            averageMinutes: mins.isEmpty ? nil : mins.reduce(0, +) / Double(mins.count),
            averageBedtime: Self.averageClock(inside.compactMap(\.bedtime), pivot: 12 * 60),
            averageWake: Self.averageClock(inside.compactMap(\.wake), pivot: 0))
    }

    /// 时间的平均；早于 pivot 的加一天再算（入睡用中午做分界，起床不用）
    static func averageClock(_ times: [String], pivot: Double) -> String? {
        let mins = times.compactMap(HealthStore.clockMinutes).map { $0 < pivot ? $0 + 1440 : $0 }
        guard !mins.isEmpty else { return nil }
        let avg = Int((mins.reduce(0, +) / Double(mins.count)).rounded()) % 1440
        return String(format: "%02d:%02d", avg / 60, avg % 60)
    }

    /// 入睡时间画图用：晚上 6 点以后照常，凌晨的加 24 小时（23:40 → 23.67，00:30 → 24.5）
    public static func bedtimeHour(_ s: String) -> Double? {
        guard let m = HealthStore.clockMinutes(s) else { return nil }
        return (m < 18 * 60 ? m + 1440 : m) / 60
    }

    /// 起床时间画图用：和入睡放在同一根轴上（起床总在午夜以后，加 24 小时）
    public static func wakeHour(_ s: String) -> Double? {
        guard let m = HealthStore.clockMinutes(s) else { return nil }
        return (m < 18 * 60 ? m + 1440 : m) / 60
    }
}

// MARK: - 睡眠和训练、考试放在一起看

/// 把睡眠按“前一天练没练”“第二天有没有考试”分开平均。只陈述，不下结论。
public struct SleepComparison: Equatable, Sendable {
    /// 练了那天晚上（起床那天的前一天有训练）
    public var afterTraining: Double?
    public var afterTrainingCount: Int
    /// 没练的那天晚上
    public var afterRest: Double?
    public var afterRestCount: Int
    /// 考试前一晚（起床那天有考试）
    public var beforeExam: Double?
    public var beforeExamCount: Int

    /// trainingDays / examDays：那天的 0 点
    public static func compute(_ nights: [SleepNight], trainingDays: Set<Date>, examDays: Set<Date>,
                               calendar: Calendar) -> SleepComparison {
        func avg(_ ns: [SleepNight]) -> Double? {
            let m = ns.compactMap(\.minutes)
            return m.isEmpty ? nil : m.reduce(0, +) / Double(m.count)
        }
        let timed = nights.filter { $0.minutes != nil }
        let trained = timed.filter { n in
            calendar.date(byAdding: .day, value: -1, to: n.date).map { trainingDays.contains(calendar.startOfDay(for: $0)) } ?? false
        }
        let rested = timed.filter { n in !trained.contains(n) }
        let exam = timed.filter { examDays.contains(calendar.startOfDay(for: $0.date)) }
        return SleepComparison(afterTraining: avg(trained), afterTrainingCount: trained.count,
                               afterRest: avg(rested), afterRestCount: rested.count,
                               beforeExam: avg(exam), beforeExamCount: exam.count)
    }
}
