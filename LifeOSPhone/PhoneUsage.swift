import AppIntents
import UIKit
import LifeOSCore

/// 睡眠自动记：记下“什么时候在用手机”，早上第一次用的时候推算昨晚几点睡、几点起，补进 `健康/睡眠/`。
/// iOS 不让 App 在后台知道手机什么时候锁屏、解锁，所以事件来自三处：
/// 1. LifeOS 自己回到前台 / 进后台；
/// 2. LifeOS 在后台活着时（比如在放听书）的锁屏 / 解锁；
/// 3. 用户在“快捷指令”里设的自动化：打开 / 关闭常用 App 时运行“记一下用了手机”（`RecordPhoneUseIntent`）。
/// 只补起床那天还没有记录的（手动记的、电脑上改过的都不动）。健康插件关着时什么都不写。
@MainActor
enum PhoneUsage {
    static let eventsKey = "phoneUseEvents"
    /// 已经推算过的起床日（不重复写，也不在用户删掉那一行后又写回去）
    static let doneKey = "sleepInferredDays"

    static var events: [Date] {
        (UserDefaults.standard.array(forKey: eventsKey) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }

    /// 记一次“在用手机”，顺便看看能不能推算昨晚。返回推算出来、写进去的那一晚（没写就 nil）
    @discardableResult
    static func record(_ now: Date = Date(), vault: URL? = nil) -> (bed: Date, wake: Date)? {
        let d = UserDefaults.standard
        // 只留 3 天
        var ev = events.filter { now.timeIntervalSince($0) < 3 * 86400 }
        ev.append(now)
        d.set(ev.map(\.timeIntervalSince1970), forKey: eventsKey)
        return inferIfNeeded(now: now, events: ev, vault: vault)
    }

    private static func inferIfNeeded(now: Date, events: [Date], vault: URL?) -> (bed: Date, wake: Date)? {
        let cal = Calendar.current
        let day = DateText.format(now, withTime: false, calendar: cal)
        var done = UserDefaults.standard.stringArray(forKey: doneKey) ?? []
        guard !done.contains(day),
              let night = SleepInference.lastNight(events: events, now: now, calendar: cal) else { return nil }
        guard let wrote = withVault(vault, { root -> Bool? in
            guard LifeConfig.load(vault: root).plugins.health else { return nil }
            return try? HealthStore(vault: root).addInferredSleep(bed: night.bed, wake: night.wake, calendar: cal)
        }) else { return nil }
        // 写了、或者那天已经有记录：都算这天处理过了
        done.append(day)
        UserDefaults.standard.set(Array(done.suffix(30)), forKey: doneKey)
        return wrote ? night : nil
    }

    /// App 在前台时用 PhoneModel 已经打开的 vault；快捷指令在后台叫起来时自己解析 bookmark
    private static func withVault<T>(_ vault: URL?, _ body: (URL) -> T?) -> T? {
        if let vault { return body(vault) }
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "debugVaultPath") { return body(URL(fileURLWithPath: path)) }
        #endif
        guard let data = UserDefaults.standard.data(forKey: PhoneModel.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }
        return PhoneModel.findVault(in: url).flatMap(body)
    }

    /// LifeOS 在后台活着时（放听书、组间计时）也记锁屏 / 解锁
    static func observeLock() {
        let nc = NotificationCenter.default
        for name in [UIApplication.protectedDataWillBecomeUnavailableNotification, UIApplication.protectedDataDidBecomeAvailableNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { _ = record() }
            }
        }
    }
}

/// 快捷指令里的动作：“记一下用了手机”。在“快捷指令 → 自动化 → App”里选常用的 App，
/// “已打开”和“已关闭”都勾上、选“立即运行”、关掉“运行时通知”，动作选这个。
struct RecordPhoneUseIntent: AppIntent {
    static let title: LocalizedStringResource = "记一下用了手机"
    static let description = IntentDescription("LifeOS 用它推算睡眠：晚上最后一次用手机到早上第一次用。只在后台记一个时间，不打开 App。")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        PhoneUsage.record()
        return .result()
    }
}

struct LifeOSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordPhoneUseIntent(), phrases: ["用 \(.applicationName) 记一下用了手机"],
                    shortTitle: "记一下用了手机", systemImageName: "iphone")
    }
}
