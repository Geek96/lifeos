import Foundation

/// 专注时的“离开”怎么算（手机版 `FocusModel` 用）：
/// LifeOS 进后台算开始离开，回到前台结算；中间锁着屏的时间扣掉，剩下超过 15 秒才记一次。
/// 锁屏靠两条线索：系统的锁屏 / 解锁通知，和 App 活着时每秒看一次“现在锁没锁”。
/// 锁屏通知大约晚 10 秒才来，所以记锁屏时往前推 10 秒（不早于进后台那一刻）。
/// 后台期间每秒一次的检查断过（App 被系统挂起了），那段分不清是锁屏还是在用别的 App，按锁屏算，这次不记离开。
public struct FocusAway: Equatable, Sendable {
    /// 离开超过这么久才算一次（拉一下通知中心、接个验证码不算）
    public static let minimum: TimeInterval = 15
    /// 锁屏通知比真正锁屏晚多久
    public static let lockDelay: TimeInterval = 10
    /// 两次检查隔了这么久，就当 App 中间被挂起过
    public static let suspendGap: TimeInterval = 5

    /// 结算一次离开的结果
    public enum Outcome: Equatable, Sendable {
        /// 记一次离开，`seconds` 是扣掉锁屏后的时长
        case left(seconds: TimeInterval)
        /// 太短，或者全在锁屏
        case ignored
        /// 中间 App 被挂起过，分不清，不记
        case suspended
    }

    public private(set) var since: Date?
    private var lockedSince: Date?
    private var lockedSeconds: TimeInterval = 0
    private var lastCheck: Date?
    private var wasSuspended = false

    public init() {}

    public var isAway: Bool { since != nil }

    /// LifeOS 进了后台
    public mutating func leave(at now: Date) {
        guard since == nil else { return }
        since = now
        lockedSince = nil
        lockedSeconds = 0
        lastCheck = now
        wasSuspended = false
    }

    /// 收到锁屏通知（或检查时发现锁着）；`delayed` 表示时间点比真正锁屏晚了 `lockDelay`
    public mutating func lock(at now: Date, delayed: Bool = true) {
        guard let since, lockedSince == nil else { return }
        lockedSince = max(delayed ? now.addingTimeInterval(-Self.lockDelay) : now, since)
    }

    /// 解锁
    public mutating func unlock(at now: Date) {
        guard let start = lockedSince else { return }
        lockedSeconds += max(now.timeIntervalSince(start), 0)
        lockedSince = nil
    }

    /// App 活着时每秒调一次；`locked` = 现在锁着屏
    public mutating func check(at now: Date, locked: Bool) {
        guard since != nil else { return }
        if let last = lastCheck, now.timeIntervalSince(last) > Self.suspendGap {
            wasSuspended = true
        }
        lastCheck = now
        if locked { lock(at: now) } else { unlock(at: now) }
    }

    /// 回到 LifeOS：结算这次离开，清空状态
    public mutating func back(at now: Date) -> Outcome {
        guard let start = since else { return .ignored }
        // 回来这一下本身也看一眼有没有隔太久（挂起后直接被唤醒回前台）
        if let last = lastCheck, now.timeIntervalSince(last) > Self.suspendGap {
            wasSuspended = true
        }
        unlock(at: now)
        let suspended = wasSuspended
        let away = max(now.timeIntervalSince(start) - lockedSeconds, 0)
        self = FocusAway()
        if suspended { return .suspended }
        return away > Self.minimum ? .left(seconds: away) : .ignored
    }
}
