import SwiftUI
import LifeOSCore

/// 手机版：只读。内容由电脑决定，手机通过 Möbius Sync（Syncthing，设成“仅接收”）拿到 vault，这里只读不写。
/// 用户在“文件”里选同步过来的文件夹（选 vault 本身或它的上级都行）；选上级时 CourseOS 学期目录也在授权范围内。
@Observable
@MainActor
final class PhoneModel {
    static let bookmarkKey = "folderBookmark"

    /// 用户选的文件夹（安全作用域，一直开着）
    private(set) var picked: URL?
    private(set) var vaultRoot: URL?
    var setupError: String?
    var courseError: String?

    var config = LifeConfig()
    var items: [LifeItem] = []
    var snapshot = CourseOSSnapshot.empty
    var health = HealthSnapshot.empty
    var things: [Thing] = []
    var finance = FinanceSnapshot.empty
    var trips: [Trip] = []
    var vision = VisionSnapshot.empty
    var lastLoad: Date?
    var clock = Date()

    let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    // MARK: - 选文件夹

    func boot() {
        #if DEBUG
        // 模拟器调试：启动参数 `-debugVaultPath <Mac 上的路径>` 直接读，不走文件选择
        if let path = UserDefaults.standard.string(forKey: "debugVaultPath") {
            open(URL(fileURLWithPath: path), saveBookmark: false, scoped: false)
            return
        }
        #endif
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
            setupError = "之前选的文件夹找不到了，重新选一次"
            return
        }
        open(url, saveBookmark: stale)
    }

    func choose(_ url: URL) {
        open(url, saveBookmark: true)
    }

    private func open(_ url: URL, saveBookmark: Bool, scoped: Bool = true) {
        picked?.stopAccessingSecurityScopedResource()
        guard !scoped || url.startAccessingSecurityScopedResource() else {
            setupError = "没有权限读这个文件夹，重新选一次"
            return
        }
        picked = url
        guard let vault = Self.findVault(in: url) else {
            vaultRoot = nil
            setupError = "这个文件夹里没找到 LifeOS vault（有 lifeos.json 或 .lifeos/ 的文件夹）"
            return
        }
        if saveBookmark, let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
        setupError = nil
        vaultRoot = vault
        reload()
    }

    /// 选的就是 vault，或者往下找三层
    static func findVault(in url: URL) -> URL? {
        let fm = FileManager.default
        func isVault(_ u: URL) -> Bool {
            fm.fileExists(atPath: LifeConfig.fileURL(vault: u).path) || VaultStore(root: u).looksValid
        }
        var level = [url]
        for _ in 0...3 {
            if let hit = level.first(where: isVault) { return hit }
            level = level.flatMap { dir in
                ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
            }
        }
        return nil
    }

    // MARK: - 载入（只读）

    func reload() {
        guard let root = vaultRoot else { return }
        config = LifeConfig.load(vault: root)
        items = VaultStore(root: root).loadItems(calendar: calendar)
        health = config.plugins.health ? HealthStore(vault: root).load(calendar: calendar) : .empty
        things = config.plugins.things ? ThingStore(vault: root).load(calendar: calendar) : []
        finance = config.plugins.finance ? FinanceStore(vault: root).load(calendar: calendar) : .empty
        trips = config.plugins.travel ? TravelStore(vault: root).loadTrips(calendar: calendar) : []
        vision = config.plugins.vision ? VisionStore(vault: root).load(calendar: calendar) : .empty
        if let semesterURL = config.courseos.resolvedSemesterURL(vault: root) {
            do {
                snapshot = try CourseOSBridge.load(semester: semesterURL, calendar: calendar)
                courseError = nil
            } catch {
                snapshot = .empty
                courseError = "没读到课程（CourseOS 学期目录没同步到手机，或者选的文件夹不包含它）"
            }
        } else {
            snapshot = .empty
            courseError = nil
        }
        lastLoad = Date()
        clock = Date()
    }

    // MARK: - 日历数据（和电脑版 AppModel 同一套算法）

    func occurrences(in range: DateInterval) -> [Occurrence] {
        let life = items.flatMap { Recurrence.occurrences(of: $0, in: range, calendar: calendar) }
        let course = CourseOSBridge.occurrences(snapshot, in: range, config: config, calendar: calendar)
        let owned = ThingCalendar.occurrences(things, in: range, calendar: calendar)
        let charges = vaultRoot.map {
            FinanceCalendar.occurrences(finance.subscriptions, fileURL: FinanceStore(vault: $0).subscriptionsURL, in: range, calendar: calendar)
        } ?? []
        let travel = TravelCalendar.occurrences(trips, in: range, calendar: calendar)
        let plans = VisionCalendar.occurrences(vision, in: range, calendar: calendar)
        return (life + course + owned + charges + travel + plans).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// 负荷：多看 5 天，让截止前摊下来的课业算进来
    func loads(for range: DateInterval) -> [Date: DayLoad] {
        let wide = DateInterval(start: range.start, end: range.end.addingTimeInterval(5 * 86400))
        var c = config
        c.layers = .init(classes: true, courseDeadlines: true, courseOptional: false)
        let life = items.flatMap { Recurrence.occurrences(of: $0, in: wide, calendar: calendar) }
        let course = CourseOSBridge.occurrences(snapshot, in: wide, config: c, calendar: calendar)
        return Insights.loads(life + course, calendar: calendar)
    }

    func dayRange(_ day: Date) -> DateInterval {
        let s = calendar.startOfDay(for: day)
        return DateInterval(start: s, end: calendar.date(byAdding: .day, value: 1, to: s) ?? s)
    }

    var upcoming: [Occurrence] { Insights.upcoming(items, now: clock, calendar: calendar) }
}
