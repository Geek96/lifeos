import SwiftUI
import AppKit
import LifeOSCore

/// 编排：载入 vault + CourseOS 快照、生成日历上的出现、处理用户操作。
/// 只写 LifeOS vault（事项时间/状态字段、新建事项、收件箱）和 lifeos.json；CourseOS 只读。
@Observable
@MainActor
final class AppModel {
    enum Page: Hashable { case today, week, month, inbox, notes }

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
    var lastLoad: Date?

    /// 周 / 月视图停在哪一天
    var anchor = Date()
    var selected: Occurrence?
    var showInspector = true
    var editor: EditorRequest?
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
        let semester = config.courseos.semester
        if semester.isEmpty {
            snapshot = .empty
            courseError = nil
        } else {
            do {
                snapshot = try CourseOSBridge.load(semester: URL(fileURLWithPath: semester), calendar: calendar)
                courseError = nil
            } catch {
                snapshot = .empty
                courseError = "找不到 CourseOS 学期目录（没有 courseos.json）"
            }
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
        if !config.courseos.semester.isEmpty {
            let sem = URL(fileURLWithPath: config.courseos.semester)
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

    // MARK: - 日历数据

    /// 某段时间内日历上的所有出现（生活 + 课程图层），按开始时间排序
    func occurrences(in range: DateInterval) -> [Occurrence] {
        let life = items.flatMap { Recurrence.occurrences(of: $0, in: range, calendar: calendar) }
        let course = CourseOSBridge.occurrences(snapshot, in: range, config: config, calendar: calendar)
        return (life + course).sorted { ($0.start, $0.title) < ($1.start, $1.title) }
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

    /// 拖动改时间（重复事项拖动的是整个系列）
    func move(_ occurrence: Occurrence, to newStart: Date) {
        guard let item = item(for: occurrence), let store else { return }
        let shift = newStart.timeIntervalSince(occurrence.start)
        guard abs(shift) >= 60 else { return }
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

    func capture(_ text: String) {
        guard let store else { return }
        do {
            try store.appendInbox(text)
            reload()
            feedback.show("已记进收件箱")
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

    // MARK: - 打开与交给 agent

    func openInObsidian(_ url: URL) {
        var comps = URLComponents()
        comps.scheme = "obsidian"
        comps.host = "open"
        comps.queryItems = [URLQueryItem(name: "path", value: url.path)]
        if let link = comps.url, NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openWeb(_ url: URL) {
        if !NSWorkspace.shared.open(url) { feedback.show("打不开链接：\(url.absoluteString)") }
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    /// 在 vault 目录里开一个 Claude Code 会话并预填指令（不自动发送）；不可用时复制到剪贴板。
    func handToAgent(_ prompt: String) {
        guard let root = vaultRoot else { return }
        if let link = AgentDeepLink.claudeCode(cwd: root, prompt: prompt),
           NSWorkspace.shared.urlForApplication(toOpen: link) != nil {
            NSWorkspace.shared.open(link)
            feedback.show("已在 Claude Code 里打开，确认后发送")
        } else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(prompt, forType: .string)
            feedback.show("指令已复制，粘贴到你正在用的 agent 对话里")
        }
    }

    func agentPromptInbox() -> String {
        """
        在 LifeOS vault 里整理收件箱。先读 .lifeos/RULES.md，按 life-manager skill 的“整理收件箱”流程做：
        逐条告诉我你打算建成什么（类型、时间），我同意后再写进 事项/，建好的从 收件箱.md 删掉，拿不准的留着。
        最后在 .lifeos/journal.md 追加一段日志。
        """
    }

    func agentPromptPrepare(_ item: LifeItem) -> String {
        """
        在 LifeOS vault 里为事项「\(item.title)」补准备信息（文件：\(item.fileURL.path)）。
        先读 .lifeos/RULES.md，按 life-manager skill 的“补准备信息”流程：只写正文，不改时间字段；
        需要查的（地址、路程、要带的材料、官方要求）查清楚并写来源，拿不准的问我。最后追加 journal。
        """
    }
}

extension Insights {
    /// 下一个整点
    static func roundUpHour(_ d: Date, _ calendar: Calendar) -> Date {
        let start = calendar.dateInterval(of: .hour, for: d)?.start ?? d
        return calendar.date(byAdding: .hour, value: 1, to: start) ?? d
    }
}
