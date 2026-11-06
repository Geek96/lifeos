import SwiftUI
import LifeOSCore

/// 专注计时（参考 Forest，但不锁 App、不种树、不惩罚）：
/// 选做什么、多久（或正计时）→ 开始；中途切到别的 App 记一次“离开”和离开多久（锁屏不算离开）；
/// 结束时可以写一句做了什么，追加到 `健康/专注/当天.md`；可以接着休息 5 分钟。
/// 进行中的状态存在 UserDefaults，App 被杀掉回来还能接上。
@Observable
@MainActor
final class FocusModel {
    enum Phase: Equatable {
        case idle
        /// end = nil 是正计时
        case focusing(start: Date, end: Date?)
        case resting(end: Date)
    }

    static let stateKey = "focusRunning"
    static let presets: [Int] = [25, 45, 60, 90]
    static let notificationID = "lifeos-focus"

    private(set) var phase: Phase = .idle
    var label = ""
    /// 这次选的分钟数；0 = 正计时
    var plannedMinutes = 25
    var restMinutes = 5
    private(set) var leaves = 0
    private(set) var leaveSeconds: Double = 0
    /// 刚结束、等着写备注的那段
    var pending: FocusSession?

    private var awaySince: Date?

    init() {
        restore()
        let nc = NotificationCenter.default
        // 锁屏：之前切出去的那段算离开，之后锁着的时间不算
        nc.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.locked() }
        }
    }

    var isFocusing: Bool { if case .focusing = phase { true } else { false } }

    // MARK: - 开始 / 结束

    func start(now: Date = Date()) {
        let end = plannedMinutes > 0 ? now.addingTimeInterval(Double(plannedMinutes) * 60) : nil
        phase = .focusing(start: now, end: end)
        leaves = 0
        leaveSeconds = 0
        awaySince = nil
        AudioCue.requestNotifications()
        AudioCue.shared.hold("focus")
        if let end {
            // App 一直活着时到点自己说；被系统杀了才靠通知（晚几秒，活着时会先取消掉）
            AudioCue.notify(Self.notificationID, at: end.addingTimeInterval(3), title: "专注结束", body: label.isEmpty ? "休息一下" : "「\(label)」结束了，休息一下")
        }
        save()
    }

    /// 到点或者提前结束：算出这段的记录放进 `pending`，等用户写一句再存
    func finish(now: Date = Date()) {
        guard case .focusing(let start, let end) = phase else { return }
        settleAway(until: now)
        let stop = min(now, end ?? now)
        let minutes = max(stop.timeIntervalSince(start) - leaveSeconds, 0) / 60
        pending = FocusSession(start: start, end: stop, minutes: minutes, label: label.trimmingCharacters(in: .whitespaces),
                               leaves: leaves, leaveMinutes: leaveSeconds / 60)
        phase = .idle
        AudioCue.cancel(Self.notificationID)
        AudioCue.shared.release("focus")
        save()
    }

    /// 放弃这段，不记
    func discard() {
        phase = .idle
        pending = nil
        AudioCue.cancel(Self.notificationID)
        AudioCue.shared.release("focus")
        save()
    }

    func startRest(now: Date = Date()) {
        let end = now.addingTimeInterval(Double(restMinutes) * 60)
        phase = .resting(end: end)
        AudioCue.shared.hold("focus")
        AudioCue.notify(Self.notificationID, at: end.addingTimeInterval(3), title: "休息结束", body: "可以开始下一段了")
        save()
    }

    func endRest() {
        phase = .idle
        AudioCue.cancel(Self.notificationID)
        AudioCue.shared.release("focus")
        save()
    }

    /// 每秒看一次：到点就结束、说一句
    func tick(now: Date = Date()) {
        switch phase {
        case .focusing(_, let end?) where now >= end:
            AudioCue.shared.say("专注结束。\(label.isEmpty ? "" : label + "，")一共 \(plannedMinutes) 分钟。休息一下吧。")
            finish(now: end)
        case .resting(let end) where now >= end:
            AudioCue.shared.say("休息结束。")
            endRest()
        default:
            break
        }
    }

    // MARK: - 离开（切到别的 App）

    func didLeave(now: Date = Date()) {
        guard isFocusing, awaySince == nil else { return }
        awaySince = now
    }

    func didReturn(now: Date = Date()) {
        settleAway(until: now)
        tick(now: now)
    }

    private func locked() {
        // 锁屏通知大约在锁屏 10 秒后才来
        settleAway(until: Date().addingTimeInterval(-10))
    }

    /// 离开超过 15 秒才算一次（拉一下通知中心、接个验证码不算）
    private func settleAway(until now: Date) {
        guard let since = awaySince else { return }
        awaySince = nil
        let away = now.timeIntervalSince(since)
        if away > 15 {
            leaves += 1
            leaveSeconds += away
        }
        save()
    }

    // MARK: - 存取进行中的状态

    private struct Saved: Codable {
        var start: Date?
        var end: Date?
        var restEnd: Date?
        var label: String
        var planned: Int
        var leaves: Int
        var leaveSeconds: Double
    }

    private func save() {
        var s = Saved(label: label, planned: plannedMinutes, leaves: leaves, leaveSeconds: leaveSeconds)
        switch phase {
        case .idle: break
        case .focusing(let start, let end): s.start = start; s.end = end
        case .resting(let end): s.restEnd = end
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(s), forKey: Self.stateKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.stateKey),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        label = s.label
        plannedMinutes = s.planned
        leaves = s.leaves
        leaveSeconds = s.leaveSeconds
        if let start = s.start {
            phase = .focusing(start: start, end: s.end)
            AudioCue.shared.hold("focus")
        } else if let end = s.restEnd {
            phase = .resting(end: end)
        }
        tick()
    }
}
