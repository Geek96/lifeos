import SwiftUI
import LifeOSCore

/// 练的时候用：按训练计划列出今天的动作，做完一组点一下 → 自动开始组间休息 → 到点在耳机里说下一组练什么。
/// 休息时长按动作来（`Exercise.defaultRest`），休息时 ±15 秒会记住，下次这个动作就用调过的；
/// 上一组没做满目标次数，这次多休息 30 秒。练完在 `健康/训练记录/` 新建一个文件。
/// 进行中的状态存在 UserDefaults，App 被杀掉回来还能接上。
@Observable
@MainActor
final class WorkoutModel {
    struct Item: Codable, Equatable, Identifiable {
        var id: String { name }
        var name: String
        var sets: Int
        var reps: Double
        /// 计时动作的“次数”是秒
        var timed: Bool
        var unit: String
        var weight: Double?
        var step: Double
        var rest: Double
    }

    struct Rest: Codable, Equatable {
        var start: Date
        var end: Date
        /// 这次因为没做满多给的秒数（不算进记住的休息时长）
        var bonus: Double
        var said10 = false
    }

    private struct Saved: Codable {
        var title: String
        var start: Date
        var items: [Item]
        var done: [LoggedSet]
        var current: Int
        var rest: Rest?
    }

    static let stateKey = "workoutRunning"
    static let restMemoryKey = "workoutRestSeconds"
    static let voiceKey = "workoutVoice"
    static let notificationID = "lifeos-rest"

    private(set) var title = ""
    private(set) var start: Date?
    private(set) var items: [Item] = []
    private(set) var done: [LoggedSet] = []
    var current = 0
    private(set) var rest: Rest?
    var voice: Bool { didSet { UserDefaults.standard.set(voice, forKey: Self.voiceKey) } }
    /// 训练页开着没有（全屏页挂在最外层，从今天页打开）
    var presented = false

    var isActive: Bool { start != nil }

    init() {
        voice = UserDefaults.standard.object(forKey: Self.voiceKey) as? Bool ?? true
        restore()
    }

    // MARK: - 今天练什么

    /// 训练计划里某一天（`周一` …）的动作；有氧（跑步）不在这里记组
    static func items(for day: WeekPlan.Day, exercises: [Exercise]) -> [Item] {
        let memory = UserDefaults.standard.dictionary(forKey: restMemoryKey) as? [String: Double] ?? [:]
        return day.exercises.compactMap { name in
            let ex = exercises.first { $0.name == name }
            if ex?.kind == .cardio || (ex == nil && name.contains("跑")) { return nil }
            let goal = ex?.targetSetsReps ?? (3, 10)
            return Item(name: name, sets: goal.sets, reps: goal.reps, timed: ex?.kind == .timed, unit: ex?.unit ?? "lb",
                        weight: ex?.kind == .strength ? ex?.suggestedWeight : nil, step: ex?.step ?? 5,
                        rest: memory[name] ?? ex?.defaultRest ?? 90)
        }
    }

    /// 今天是训练计划里的哪一天
    static func planDay(_ plan: WeekPlan, on date: Date, calendar: Calendar) -> WeekPlan.Day? {
        let w = calendar.component(.weekday, from: date)  // 周日 = 1
        let index = (w + 5) % 7 + 1                        // 周一 = 1 … 周日 = 7
        return plan.days.first { WeekPlan.index(of: $0.weekday) == index && !$0.exercises.isEmpty }
    }

    // MARK: - 开始 / 结束

    func begin(title: String, items: [Item], now: Date = Date()) {
        self.title = title
        self.items = items
        start = now
        done = []
        current = 0
        rest = nil
        AudioCue.requestNotifications()
        AudioCue.shared.hold("workout")
        save()
    }

    /// 练完：交给 PhoneModel 写训练记录；写成了才清掉
    func finish(model: PhoneModel, note: String, now: Date = Date()) -> Bool {
        guard let start else { return false }
        endRest(now: now)
        let short = title.replacingOccurrences(of: #"（.*）|\(.*\)|\s"#, with: "", options: .regularExpression)
        guard done.isEmpty || model.saveWorkout(title: "力量 · \(title)", fileTitle: short.isEmpty ? "力量" : short,
                                                start: start, end: now, sets: done, note: note) else { return false }
        discard()
        return true
    }

    func discard() {
        start = nil
        items = []
        done = []
        rest = nil
        AudioCue.cancel(Self.notificationID)
        AudioCue.shared.release("workout")
        save()
    }

    // MARK: - 一组

    func setsDone(_ item: Item) -> [LoggedSet] { done.filter { $0.exercise == item.name } }

    var currentItem: Item? { items.indices.contains(current) ? items[current] : nil }

    func setWeight(_ w: Double?) {
        guard items.indices.contains(current) else { return }
        items[current].weight = w
        save()
    }

    /// 做完一组：记下来，开始休息。这个动作做满了就跳到下一个还没做完的动作
    func completeSet(reps: Double, now: Date = Date()) {
        guard let item = currentItem else { return }
        endRest(now: now)
        done.append(LoggedSet(exercise: item.name, weight: item.weight, reps: reps))
        if setsDone(item).count >= item.sets, let next = nextUnfinished(after: current) {
            current = next
        }
        let bonus: Double = reps < item.reps ? 30 : 0
        let all = items.allSatisfy { setsDone($0).count >= $0.sets }
        if !all {
            let r = Rest(start: now, end: now.addingTimeInterval(item.rest + bonus), bonus: bonus)
            rest = r
            AudioCue.notify(Self.notificationID, at: r.end.addingTimeInterval(3), title: "休息结束", body: nextText)
            if voice, bonus > 0 { AudioCue.shared.say("这组没做满，多休息 30 秒。") }
        } else if voice {
            AudioCue.shared.say("全部做完了。")
        }
        save()
    }

    /// 再加一组 / 撤销上一组
    func undoLast() {
        guard let last = done.popLast() else { return }
        rest = nil
        AudioCue.cancel(Self.notificationID)
        if let i = items.firstIndex(where: { $0.name == last.exercise }) { current = i }
        save()
    }

    private func nextUnfinished(after i: Int) -> Int? {
        let order = Array(items.indices[(i + 1)...]) + Array(items.indices[..<i])
        return order.first { setsDone(items[$0]).count < items[$0].sets }
    }

    // MARK: - 休息

    /// ±15 秒；记住这个动作以后的休息时长
    func adjustRest(_ delta: Double) {
        guard var r = rest, let i = items.firstIndex(where: { $0.name == done.last?.exercise }) else { return }
        r.end = max(r.end.addingTimeInterval(delta), Date())
        if r.end.timeIntervalSinceNow > 10 { r.said10 = false }
        rest = r
        items[i].rest = max(items[i].rest + delta, 15)
        var memory = UserDefaults.standard.dictionary(forKey: Self.restMemoryKey) as? [String: Double] ?? [:]
        memory[items[i].name] = items[i].rest
        UserDefaults.standard.set(memory, forKey: Self.restMemoryKey)
        AudioCue.cancel(Self.notificationID)
        AudioCue.notify(Self.notificationID, at: r.end.addingTimeInterval(3), title: "休息结束", body: nextText)
        save()
    }

    func skipRest() { endRest(now: Date()) }

    /// 记下上一组之后实际休息了多久
    private func endRest(now: Date) {
        guard let r = rest else { return }
        if !done.isEmpty { done[done.count - 1].rest = now.timeIntervalSince(r.start).rounded() }
        rest = nil
        AudioCue.cancel(Self.notificationID)
        save()
    }

    /// 每秒看一次：剩 10 秒说一声，到点说下一组
    func tick(now: Date = Date()) {
        guard var r = rest else { return }
        let left = r.end.timeIntervalSince(now)
        if left <= 10, left > 0, !r.said10 {
            r.said10 = true
            rest = r
            if voice { AudioCue.shared.say("还有 10 秒") }
            save()
        }
        if left <= 0 {
            if voice { AudioCue.shared.say("休息结束。" + nextText) }
            // 休息到点了不算“实际休息”的结束：等用户点做完下一组时再算
            rest = nil
            AudioCue.cancel(Self.notificationID)
            if !done.isEmpty, done[done.count - 1].rest == nil { done[done.count - 1].rest = now.timeIntervalSince(r.start).rounded() }
            save()
        }
    }

    /// “下一组：卧推，第 2 组，95 磅，8 个”
    var nextText: String {
        guard let item = currentItem else { return "" }
        let n = setsDone(item).count + 1
        var parts = ["下一组：\(item.name)", "第 \(n) 组"]
        if let w = item.weight { parts.append("\(WorkoutFmt.num(w)) \(item.unit == "lb" ? "磅" : item.unit)") }
        parts.append(item.timed ? "\(WorkoutFmt.num(item.reps)) 秒" : "\(WorkoutFmt.num(item.reps)) 个")
        return parts.joined(separator: "，")
    }

    // MARK: - 存取

    private func save() {
        guard let start else {
            UserDefaults.standard.removeObject(forKey: Self.stateKey)
            return
        }
        let s = Saved(title: title, start: start, items: items, done: done, current: current, rest: rest)
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: Self.stateKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        title = s.title
        start = s.start
        items = s.items
        done = s.done
        current = s.current
        rest = s.rest
        AudioCue.shared.hold("workout")
    }
}

enum WorkoutFmt {
    static func num(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}
