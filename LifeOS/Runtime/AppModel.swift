import SwiftUI
import AppKit
import LifeOSCore

/// 编排：载入 vault + CourseOS 快照、生成日历上的出现、处理用户操作。
/// 只写 LifeOS vault（事项时间/状态字段、新建事项、收件箱、健康插件的饮食表追加一行、睡眠表记一晚、体重表记一次、购物清单、备餐）和 lifeos.json；CourseOS 只读。
@Observable
@MainActor
final class AppModel {
    enum Page: Hashable {
        case today, week, month, inbox, notes, nutrition, fitness, rest, things, finance, travel, vision

        /// 健康插件的三页：营养 / 健身与锻炼 / 休息与放松
        var isHealth: Bool { self == .nutrition || self == .fitness || self == .rest }
    }

    /// 新建 / 编辑事项的 sheet
    struct EditorRequest: Identifiable {
        let id = UUID()
        var item: LifeItem?
        var kind: LifeItem.Kind = .event
        var start: Date
        var title: String = ""
    }

    static let vaultKey = "vaultPath"
    static let defaultVault = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/LifeOS")

    var page: Page? = .today
    var vaultRoot: URL?
    var config = LifeConfig()
    var items: [LifeItem] = []
    var snapshot = CourseOSSnapshot.empty
    /// CourseOS 联动状态：nil = 正常或未设置
    var courseError: String?
    var inbox: [String] = []
    var notes: [VaultStore.Note] = []
    var journal: [VaultStore.JournalEntry] = []
    /// 健康插件（关着时为空）
    var health = HealthSnapshot.empty
    /// 物品插件（关着时为空）
    var things: [Thing] = []
    /// 物品插件的想买清单
    var thingWishes: [WishItem] = []
    /// 消费插件（流水、账户、订阅、预算；关着时为空）
    var finance = FinanceSnapshot.empty
    /// 出行插件
    var trips: [Trip] = []
    var wishlist: [Destination] = []
    /// 出行页正在看的那一次（nil = 列表）
    var openTripID: String?
    /// 从愿景清单点进出行详情时记住来源，返回时回到那个愿景
    var tripReturnVisionID: String?
    /// 健康页“健身”分页正在看的动作（nil = 总览）
    var openExerciseID: String?
    /// 远景插件：愿景、项目、奇思妙想
    var vision = VisionSnapshot.empty
    /// 远景页正在看的愿景 / 项目 / 想法（都为 nil = 列表）
    var openVisionID: String?
    var openProjectID: String?
    var openIdeaID: String?
    var lastLoad: Date?

    /// 周 / 月视图停在哪一天
    var anchor = Date()
    var selected: Occurrence?
    var showInspector = true
    var editor: EditorRequest?
    /// “只改这一次”表单正在编辑的那一次（重复事项）
    var onceEditor: Occurrence?
    var captureFocusRequest = 0
    /// 每分钟走一次，让“现在”线和淡出跟上
    var clock = Date()

    let feedback = Feedback()
    private var watcher: VaultWatcher?
    private var ticker: Task<Void, Never>?

    let calendar: Calendar = {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }()

    var store: VaultStore? { vaultRoot.map(VaultStore.init(root:)) }

    // MARK: - 启动与载入

    func boot() {
        let saved = UserDefaults.standard.string(forKey: Self.vaultKey).map { URL(fileURLWithPath: $0) }
        if let saved, FileManager.default.fileExists(atPath: saved.path) {
            vaultRoot = saved
        } else if FileManager.default.fileExists(atPath: Self.defaultVault.path) {
            vaultRoot = Self.defaultVault
        }
        reload()
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.clock = Date()
            }
        }
    }

    func reload() {
        guard let root = vaultRoot else { return }
        let store = VaultStore(root: root)
        config = LifeConfig.load(vault: root)
        items = store.loadItems(calendar: calendar)
        inbox = store.inboxLines()
        notes = store.notes()
        journal = store.recentJournal()
        health = config.plugins.health ? HealthStore(vault: root).load(calendar: calendar) : .empty
        if !config.plugins.health && page?.isHealth == true { page = .today }
        things = config.plugins.things ? ThingStore(vault: root).load(calendar: calendar) : []
        thingWishes = config.plugins.things ? ThingStore(vault: root).loadWishlist(calendar: calendar) : []
        finance = config.plugins.finance ? FinanceStore(vault: root).load(calendar: calendar) : .empty
        if !config.plugins.finance && page == .finance { page = .today }
        if config.plugins.travel {
            let travel = TravelStore(vault: root)
            trips = travel.loadTrips(calendar: calendar)
            wishlist = travel.loadWishlist()
        } else {
            trips = []
            wishlist = []
            if page == .travel { page = .today }
        }
        if !config.plugins.things && page == .things { page = .today }
        vision = config.plugins.vision ? VisionStore(vault: root).load(calendar: calendar) : .empty
        if !config.plugins.vision && page == .vision { page = .today }
        if let semesterURL = config.courseos.resolvedSemesterURL(vault: root) {
            do {
                snapshot = try CourseOSBridge.load(semester: semesterURL, calendar: calendar)
                courseError = nil
            } catch {
                snapshot = .empty
                courseError = "找不到 CourseOS 学期目录（没有 courseos.json）"
            }
        } else {
            snapshot = .empty
            courseError = nil
        }
        // 选中的事项被改过 / 删掉了：按 id 重新找，找不到就清空
        if let sel = selected {
            let range = DateInterval(start: calendar.startOfDay(for: sel.start), duration: 2 * 86400)
            selected = occurrences(in: range).first { $0.id == sel.id }
        }
        lastLoad = Date()
        clock = Date()
        startWatching()
    }

    private func startWatching() {
        guard let root = vaultRoot else { return }
        var paths = [root]
        if let sem = config.courseos.resolvedSemesterURL(vault: root) {
            paths += [sem.appendingPathComponent("_exports"), sem.appendingPathComponent(".courseos"),
                      sem.appendingPathComponent("courseos.json")]
        }
        watcher?.stop()
        watcher = VaultWatcher(paths: paths, latency: 0.8) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        watcher?.start()
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        panel.message = "选择 LifeOS vault 文件夹（含 事项/ 和 .lifeos/）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = VaultStore(root: url)
        if !store.looksValid {
            try? FileManager.default.createDirectory(at: store.itemsDir, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: store.notesDir, withIntermediateDirectories: true)
            feedback.show("已在 \(url.lastPathComponent) 里建好 事项/ 和 备忘/")
        }
        vaultRoot = url
        UserDefaults.standard.set(url.path, forKey: Self.vaultKey)
        reload()
    }

    func saveConfig(_ new: LifeConfig) {
        guard let root = vaultRoot else { return }
        do {
            try new.save(vault: root)
            config = new
            reload()
        } catch {
            feedback.show("保存设置失败：\(error.localizedDescription)")
        }
    }

    func setLayer(_ keyPath: WritableKeyPath<LifeConfig.Layers, Bool>, _ on: Bool) {
        var c = config
        c.layers[keyPath: keyPath] = on
        saveConfig(c)
    }

    func setPlugin(_ keyPath: WritableKeyPath<LifeConfig.Plugins, Bool>, _ on: Bool) {
        var c = config
        c.plugins[keyPath: keyPath] = on
        saveConfig(c)
    }

    // MARK: - 日历数据

    /// 某段时间内日历上的所有出现（生活 + 课程图层），按开始时间排序
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

    /// 某段时间里有考试的日子（0 点）：不受“课程截止与考试”图层开关影响
    func examDays(in range: DateInterval) -> Set<Date> {
        var c = config
        c.layers = .init(classes: false, courseDeadlines: true, courseOptional: false)
        return Set(CourseOSBridge.occurrences(snapshot, in: range, config: c, calendar: calendar)
            .filter { $0.style == .courseExam }.map { calendar.startOfDay(for: $0.start) })
    }

    /// 负荷：多看 5 天，让截止前摊下来的课业算进来（课业负荷不受图层开关影响）
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

    var weekRange: DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: anchor) ?? dayRange(anchor)
    }

    var upcoming: [Occurrence] { Insights.upcoming(items, now: clock, calendar: calendar) }

    func item(for occurrence: Occurrence?) -> LifeItem? {
        guard let id = occurrence?.itemID else { return nil }
        return items.first { $0.id == id }
    }

    /// 选中事项的提示（冲突、考试前夜、很满的一天）
    func hints(for o: Occurrence) -> [Hint] {
        let range = DateInterval(start: calendar.startOfDay(for: o.start).addingTimeInterval(-86400), duration: 4 * 86400)
        var c = config
        c.layers = .init(classes: true, courseDeadlines: true, courseOptional: false)
        let all = items.flatMap { Recurrence.occurrences(of: $0, in: range, calendar: calendar) }
            + CourseOSBridge.occurrences(snapshot, in: range, config: c, calendar: calendar)
        return Insights.hints(for: o, among: all, loads: loads(for: range), calendar: calendar)
    }

    /// 时间窗的空档建议
    func freeSlots(for item: LifeItem) -> [FreeSlot] {
        let from = max(item.start, clock)
        let until = item.end ?? item.start
        guard until > from else { return [] }
        let range = DateInterval(start: calendar.startOfDay(for: from), end: until)
        var c = config
        c.layers = .init(classes: true, courseDeadlines: true, courseOptional: false)
        let all = items.flatMap { Recurrence.occurrences(of: $0, in: range, calendar: calendar) }
            + CourseOSBridge.occurrences(snapshot, in: range, config: c, calendar: calendar)
        return Insights.freeSlots(from: from, until: until, hours: item.estimateHours ?? 1, among: all,
                                  loads: loads(for: range), dayStart: max(config.dayHours.start, 9),
                                  dayEnd: min(config.dayHours.end, 21), calendar: calendar)
    }

    // MARK: - 操作（只写 LifeOS vault）

    func newItem(kind: LifeItem.Kind = .event, at start: Date? = nil) {
        let base = start ?? Insights.roundUpHour(clock, calendar)
        editor = EditorRequest(item: nil, kind: kind, start: base)
    }

    func edit(_ item: LifeItem) {
        editor = EditorRequest(item: item, kind: item.kind, start: item.start, title: item.title)
    }

    func create(kind: LifeItem.Kind, title: String, start: Date, end: Date?, hasTime: Bool, location: String,
                repeatRule: RepeatRule?, estimate: Double?) {
        guard let store else { return }
        do {
            let url = try store.createItem(kind: kind, title: title, start: start, end: end, startHasTime: hasTime,
                                           location: location, repeatRule: repeatRule, estimateHours: estimate,
                                           calendar: calendar)
            reload()
            feedback.show("已放进日历：\(title)", undo: { [weak self] in
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                self?.reload()
            })
        } catch {
            feedback.show("没能新建：\(error.localizedDescription)")
        }
    }

    /// 改字段；可撤销（恢复原文件内容）
    func update(_ item: LifeItem, set changes: [(String, String?)], message: String) {
        guard let store else { return }
        let before = try? String(contentsOf: item.fileURL, encoding: .utf8)
        do {
            try store.updateItem(at: item.fileURL, set: changes)
            reload()
            feedback.show(message, undo: restorer(item.fileURL, before))
        } catch {
            feedback.show("没能保存：\(error.localizedDescription)")
        }
    }

    /// 拖动改时间（重复事项拖动的是整个系列；已经单独调整过的那一次只挪它自己）
    func move(_ occurrence: Occurrence, to newStart: Date) {
        guard let item = item(for: occurrence), let store else { return }
        let shift = newStart.timeIntervalSince(occurrence.start)
        guard abs(shift) >= 60 else { return }
        if occurrence.adjusted, item.repeatRule != nil, let series = occurrence.seriesStart {
            var e = exception(for: occurrence, of: item) ?? RecurrenceException(date: series)
            e.start = newStart
            e.end = occurrence.end.map { $0.addingTimeInterval(shift) }
            let f = DateFormatter()
            f.dateFormat = "M月d日 HH:mm"
            setException(e, for: occurrence, of: item, message: "已移到 \(f.string(from: newStart))（只改这一次）")
            return
        }
        let before = try? String(contentsOf: item.fileURL, encoding: .utf8)
        do {
            try store.move(item, to: item.start.addingTimeInterval(shift), calendar: calendar)
            reload()
            let f = DateFormatter()
            f.dateFormat = "M月d日 HH:mm"
            let note = item.repeatRule == nil ? "" : "（整个重复系列）"
            feedback.show("已移到 \(f.string(from: newStart))\(note)", undo: restorer(item.fileURL, before))
        } catch {
            feedback.show("没能移动：\(error.localizedDescription)")
        }
    }

    // MARK: 重复事项里的单独一次（写 frontmatter 的 exceptions）

    /// 这一次现有的例外（没有就是 nil）
    func exception(for occurrence: Occurrence, of item: LifeItem) -> RecurrenceException? {
        guard let series = occurrence.seriesStart else { return nil }
        return item.exceptions.last { calendar.isDate($0.date, inSameDayAs: series) }
    }

    func editOnce(_ occurrence: Occurrence) {
        onceEditor = occurrence
    }

    /// 取消这一次（那天不显示，其余照常）
    func skipOnce(_ occurrence: Occurrence) {
        guard let item = item(for: occurrence), let series = occurrence.seriesStart else { return }
        selected = nil
        setException(RecurrenceException(date: series, skip: true), for: occurrence, of: item,
                     message: "已取消 \(Fmt.shortDay(series)) 这一次")
    }

    /// 这一次恢复成和系列一样
    func restoreOnce(_ occurrence: Occurrence) {
        guard let item = item(for: occurrence) else { return }
        setException(nil, for: occurrence, of: item, message: "这一次已恢复原样")
    }

    /// 写入这一次的例外（nil = 删除）；可撤销
    func setException(_ e: RecurrenceException?, for occurrence: Occurrence, of item: LifeItem, message: String) {
        guard let store, let series = occurrence.seriesStart else { return }
        let before = try? String(contentsOf: item.fileURL, encoding: .utf8)
        do {
            try store.setException(e, forSeriesDate: series, of: item, calendar: calendar)
            reload()
            // id 按原本的日期，挪了时间也能继续选中
            if let s = selected, s.id == occurrence.id {
                let range = DateInterval(start: series.addingTimeInterval(-60 * 86400), duration: 120 * 86400)
                selected = Recurrence.occurrences(of: self.item(for: occurrence) ?? item, in: range, calendar: calendar)
                    .first { $0.id == occurrence.id }
            }
            feedback.show(message, undo: restorer(item.fileURL, before))
        } catch {
            feedback.show("没能保存：\(error.localizedDescription)")
        }
    }

    /// 撤销：把文件内容写回改动前
    private func restorer(_ url: URL, _ before: String?) -> (@MainActor () -> Void)? {
        guard let before else { return nil }
        return { [weak self] in
            try? before.write(to: url, atomically: true, encoding: .utf8)
            self?.reload()
        }
    }

    func toggleDone(_ item: LifeItem) {
        update(item, set: [("done", item.done ? nil : "true")], message: item.done ? "已恢复" : "办好了：\(item.title)")
    }

    /// 移到废纸篓（可在访达里找回），并支持撤销
    func trash(_ item: LifeItem) {
        var result: NSURL?
        do {
            try FileManager.default.trashItem(at: item.fileURL, resultingItemURL: &result)
            selected = nil
            reload()
            var undo: (@MainActor () -> Void)?
            if let trashed = result as URL? {
                undo = { [weak self] in
                    try? FileManager.default.moveItem(at: trashed, to: item.fileURL)
                    self?.reload()
                }
            }
            feedback.show("已移到废纸篓：\(item.title)", undo: undo)
        } catch {
            feedback.show("没能删除：\(error.localizedDescription)")
        }
    }

    func capture(_ text: String, message: String = "已记进收件箱") {
        guard let store else { return }
        do {
            try store.appendInbox(text)
            reload()
            feedback.show(message)
        } catch {
            feedback.show("没能记下：\(error.localizedDescription)")
        }
    }

    func removeInbox(_ line: String) {
        guard let store else { return }
        do {
            try store.removeInbox(line)
            reload()
            feedback.show("已从收件箱移除", undo: { [weak self] in self?.capture(line) })
        } catch {
            feedback.show("没能移除：\(error.localizedDescription)")
        }
    }

    // MARK: - 健康插件

    /// 某天的训练：属于 health 插件的事项在这一天的出现
    func training(on day: Date) -> [(occurrence: Occurrence, item: LifeItem)] {
        let range = dayRange(day)
        return items.filter { $0.plugin == "health" }
            .flatMap { item in Recurrence.occurrences(of: item, in: range, calendar: calendar).map { ($0, item) } }
            .sorted { $0.0.start < $1.0.start }
    }

    /// 打开一个动作的详情（健身与锻炼页 → 计划与动作分页）
    func openExercise(_ ex: Exercise) {
        UserDefaults.standard.set("plan", forKey: "fitnessTab")
        openExerciseID = ex.id
        page = .fitness
    }

    // MARK: 食谱、购物清单、备餐

    /// 改一个健康文件：写入新内容、重新载入、提示，撤销 = 还原（原来没有就移到废纸篓）
    private func rewriteHealthFile(_ url: URL, message: String, change: (String?) -> String) {
        let before = try? String(contentsOf: url, encoding: .utf8)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try change(before).write(to: url, atomically: true, encoding: .utf8)
            reload()
            feedback.show(message, undo: { [weak self] in
                if let before { try? before.write(to: url, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                self?.reload()
            })
        } catch {
            feedback.show("没能写入：\(error.localizedDescription)")
        }
    }

    /// 选几个食谱、各做几份，把要买的加进购物清单
    func addToShopping(_ picks: [(recipe: Recipe, servings: Int)]) {
        guard let root = vaultRoot else { return }
        let items = ShoppingList.items(for: picks)
        guard !items.isEmpty else { feedback.show("这些食谱的材料家里都有"); return }
        rewriteHealthFile(HealthStore(vault: root).shoppingURL, message: "已加进购物清单（\(items.count) 样）") {
            ShoppingList.adding(items, to: $0)
        }
    }

    func toggleShopping(_ item: ShoppingItem) {
        guard let root = vaultRoot else { return }
        let url = HealthStore(vault: root).shoppingURL
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        try? ShoppingList.toggling(item, in: text).write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    func clearShoppingDone() {
        guard let root = vaultRoot else { return }
        rewriteHealthFile(HealthStore(vault: root).shoppingURL, message: "已清掉买好的") { ShoppingList.clearingDone($0 ?? "") }
    }

    /// 记一批备餐：冷藏几个、冷冻几个（各一行）
    func recordPrep(name: String, made: Date, fridge: Int, freezer: Int) {
        guard let root = vaultRoot, fridge + freezer > 0 else { return }
        rewriteHealthFile(HealthStore(vault: root).prepURL, message: "已记下：\(name) \(fridge + freezer) 个") { text in
            var out = text
            for (place, n) in [("冷藏", fridge), ("冷冻", freezer)] where n > 0 {
                let b = PrepBatch(made: calendar.startOfDay(for: made), name: name, count: n, left: n, place: place,
                                  useBy: PrepBatch.defaultUseBy(made: made, place: place, calendar: calendar))
                out = MealPrep.adding(b, to: out, calendar: calendar)
            }
            return out ?? ""
        }
    }

    /// 吃了一个：还剩 −1，并按同名食谱的每份营养在今天的饮食表记一行（找不到食谱就记成待估算）。两处一起撤销
    func eatPrep(_ batch: PrepBatch) {
        guard let root = vaultRoot, batch.left > 0 else { return }
        let store = HealthStore(vault: root)
        let prepURL = store.prepURL, dietURL = store.dietURL(Date(), calendar: calendar)
        let prepBefore = try? String(contentsOf: prepURL, encoding: .utf8)
        let dietBefore = try? String(contentsOf: dietURL, encoding: .utf8)
        guard let prepText = prepBefore else { return }
        let recipe = health.recipes.first { $0.name == batch.name }
        do {
            try MealPrep.settingLeft(batch, to: batch.left - 1, in: prepText, calendar: calendar)
                .write(to: prepURL, atomically: true, encoding: .utf8)
            try store.appendMeal("\(batch.name) ×1（备餐）", at: Date(), nutrition: recipe?.nutrition, calendar: calendar)
            reload()
            feedback.show(recipe?.nutrition == nil ? "已记下，还剩 \(batch.left - 1) 个（营养等 agent 估算）" : "已记下，还剩 \(batch.left - 1) 个",
                          undo: { [weak self] in
                try? prepText.write(to: prepURL, atomically: true, encoding: .utf8)
                if let dietBefore { try? dietBefore.write(to: dietURL, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: dietURL, resultingItemURL: nil) }
                self?.reload()
            })
        } catch {
            feedback.show("没能记下：\(error.localizedDescription)")
        }
    }

    /// 记一次体重（“145”“65.8 kg”）；同一天再记就替换。可撤销
    @discardableResult
    func recordWeight(day: Date, value: String) -> Bool {
        guard let root = vaultRoot else { return false }
        let store = HealthStore(vault: root)
        let url = store.weightURL
        let replacing = health.weights.contains { calendar.isDate($0.date, inSameDayAs: day) }
        do {
            let before = try store.recordWeight(day: day, value: value, calendar: calendar)
            reload()
            feedback.show(replacing ? "已更新这天的体重" : "已记下体重", undo: { [weak self] in
                if let before { try? before.write(to: url, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                self?.reload()
            })
            return true
        } catch {
            feedback.show("没能记下：\(error.localizedDescription)")
            return false
        }
    }

    /// 记一晚睡眠（起床那天、几点睡、几点起，可以只填一个）；同一天再记就替换。可撤销
    @discardableResult
    func recordSleep(wakeDay: Date, bedtime: String?, wake: String?) -> Bool {
        guard let root = vaultRoot else { return false }
        let store = HealthStore(vault: root)
        let url = store.sleepURL(wakeDay, calendar: calendar)
        let replacing = health.sleep(on: wakeDay, calendar: calendar) != nil
        do {
            let before = try store.recordSleep(wakeDay: wakeDay, bedtime: bedtime, wake: wake, calendar: calendar)
            reload()
            feedback.show(replacing ? "已更新这一晚" : "已记下", undo: { [weak self] in
                if let before { try? before.write(to: url, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                self?.reload()
            })
            return true
        } catch {
            feedback.show("没能记下：\(error.localizedDescription)")
            return false
        }
    }

    /// 在今天的饮食表里记一顿（还没估算，等 agent 补数字）；可撤销
    /// `day` 不是今天时是补记：时间一栏写“补记”
    func logMeal(_ text: String, on day: Date? = nil) {
        guard let root = vaultRoot else { return }
        let store = HealthStore(vault: root)
        let target = day ?? Date()
        let isToday = calendar.isDate(target, inSameDayAs: Date())
        let url = store.dietURL(target, calendar: calendar)
        do {
            let before = try store.appendMeal(text, at: isToday ? Date() : target, time: isToday ? nil : "补记", calendar: calendar)
            reload()
            feedback.show("已记下，等 agent 估算营养", undo: { [weak self] in
                if let before { try? before.write(to: url, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                self?.reload()
            })
        } catch {
            feedback.show("没能记下：\(error.localizedDescription)")
        }
    }

    /// 日历上的物品出现 → 对应的物品
    func thing(for occurrence: Occurrence?) -> Thing? {
        guard let o = occurrence, o.id.hasPrefix("thing:") else { return nil }
        return things.first { $0.fileURL == o.sourceURL }
    }

    /// 日历上的出行出现 → 那次出行
    func trip(for occurrence: Occurrence?) -> Trip? {
        guard let o = occurrence, o.id.hasPrefix("trip:") else { return nil }
        return trips.first { $0.fileURL == o.sourceURL }
    }

    func openTrip(_ trip: Trip, from vision: Vision? = nil) {
        openTripID = trip.id
        tripReturnVisionID = vision?.id
        page = .travel
    }

    /// 出行详情页的返回：从愿景点进来的回到愿景，否则回到出行列表
    func closeTrip() {
        openTripID = nil
        if let id = tripReturnVisionID, let v = vision.visions.first(where: { $0.id == id }) {
            tripReturnVisionID = nil
            openVision(v)
        }
    }

    /// 愿景清单里的一个地方 → 对应的出行（先看“行程”列，没写就按名字找）
    func trip(for place: VisionPlace) -> Trip? {
        if !place.trip.isEmpty {
            return trips.first { $0.fileURL.deletingPathExtension().lastPathComponent == place.trip || $0.title == place.trip }
        }
        return trips.first { $0.title.localizedCaseInsensitiveContains(place.name) || $0.destination.localizedCaseInsensitiveContains(place.name) }
    }

    /// 勾选“要带”清单的一项；可撤销
    func togglePacking(_ item: PackItem, in trip: Trip) {
        guard let root = vaultRoot else { return }
        do {
            let before = try TravelStore(vault: root).togglePacking(item, in: trip)
            reload()
            feedback.show(item.done ? "已取消：\(item.text)" : "已带上：\(item.text)", undo: restorer(trip.fileURL, before))
        } catch {
            reload()
            feedback.show("文件刚被改过，已重新载入，再点一次")
        }
    }

    // MARK: - 远景插件

    /// 日历上的项目步骤 → 那个项目
    func project(for occurrence: Occurrence?) -> VisionProject? {
        guard let o = occurrence, o.id.hasPrefix("project:") else { return nil }
        return vision.projects.first { $0.fileURL == o.sourceURL }
    }

    func openVision(_ v: Vision) {
        openProjectID = nil
        openIdeaID = nil
        openVisionID = v.id
        page = .vision
    }

    func openProject(_ p: VisionProject) {
        openIdeaID = nil
        openProjectID = p.id
        page = .vision
    }

    func openIdea(_ i: Idea) {
        openProjectID = nil
        openIdeaID = i.id
        page = .vision
    }

    /// 勾选项目的一步；可撤销
    func toggleStep(_ step: ProjectStep, in project: VisionProject) {
        guard let root = vaultRoot else { return }
        do {
            let before = try VisionStore(vault: root).toggleStep(step, in: project)
            reload()
            feedback.show(step.done ? "已取消：\(step.text)" : "做完了：\(step.text)", undo: restorer(project.fileURL, before))
        } catch {
            reload()
            feedback.show("文件刚被改过，已重新载入，再点一次")
        }
    }

    /// 快速记一件东西（“名称，位置”）；可撤销
    func quickAddThing(_ text: String) {
        guard let root = vaultRoot else { return }
        do {
            let url = try ThingStore(vault: root).quickAdd(text, calendar: calendar)
            reload()
            feedback.show("已记下：\(url.deletingPathExtension().lastPathComponent)", undo: { [weak self] in
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                self?.reload()
            })
        } catch {
            feedback.show("没能记下：先写名称，再用逗号隔开位置")
        }
    }

    /// 加进想买清单；可撤销
    func addWish(_ text: String) {
        guard let root = vaultRoot else { return }
        let store = ThingStore(vault: root)
        do {
            let before = try store.appendWish(text, calendar: calendar)
            reload()
            let url = store.wishlistURL
            feedback.show("已加进想买清单", undo: { [weak self] in
                if let before { try? before.write(to: url, atomically: true, encoding: .utf8) }
                else { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
                self?.reload()
            })
        } catch {
            feedback.show("没能加进去：\(error.localizedDescription)")
        }
    }

    // MARK: - 打开

    func openWeb(_ url: URL) {
        if !NSWorkspace.shared.open(url) { feedback.show("打不开链接：\(url.absoluteString)") }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

}

extension Insights {
    /// 下一个整点
    static func roundUpHour(_ d: Date, _ calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .hour, for: d)?.start ?? d
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? d
    }
}
