import Testing
import Foundation
@testable import LifeOSCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c
}()

private func d(_ s: String) -> Date { DateText.parse(s, calendar: cal)! }
private let file = URL(fileURLWithPath: "/tmp/事项/x.md")

@Suite struct FrontmatterTests {
    @Test func parsesAndUpdatesWithoutTouchingBody() {
        let text = "---\ntype: life-item\ntitle: \"看牙: 洗牙\"\nstart: 2026-10-20 14:00 # 下午\n---\n带上保险卡\n"
        let doc = Frontmatter.parse(text)
        #expect(doc.fields["title"] == "看牙: 洗牙")
        #expect(doc.fields["start"] == "2026-10-20 14:00")
        let out = Frontmatter.update(text, set: [("start", "2026-10-21 09:00"), ("done", "true"), ("title", nil)])
        #expect(out.contains("start: 2026-10-21 09:00"))
        #expect(out.contains("done: true\n---"))
        #expect(!out.contains("title:"))
        #expect(out.hasSuffix("---\n带上保险卡\n"))
    }
}

@Suite struct LifeItemTests {
    @Test func parsesKindsAndDefaults() {
        let e = LifeItem.parse(text: "---\nkind: event\ntitle: 吃饭\nstart: 2026-10-20 18:00\n---\n", fileURL: file, calendar: cal)!
        #expect(e.kind == .event && e.duration == 3600 && !e.allDay)
        let w = LifeItem.parse(text: "---\nkind: window\ntitle: 换护照\nstart: 2026-10-15\nend: 2026-10-31\nestimate: 90m\n---\n", fileURL: file, calendar: cal)!
        #expect(w.allDay && w.estimateHours == 1.5)
        #expect(cal.component(.day, from: w.end!) == 31 && cal.component(.hour, from: w.end!) == 23)
        #expect(LifeItem.parse(text: "---\ntype: life-inbox\n---\n", fileURL: file) == nil)
    }

    @Test func repeatRules() {
        #expect(RepeatRule.parse("weekly:mon,wed") == .weekly([2, 4]))
        #expect(RepeatRule.parse("monthly:31") == .monthly(31))
        #expect(RepeatRule.weekly([2, 4]).text == "weekly:mon,wed")
        #expect(RepeatRule.weekly([2, 4]).label == "每周一、三")
    }
}

@Suite struct RecurrenceTests {
    @Test func weeklyExpandsInRange() {
        let item = LifeItem(fileURL: file, kind: .event, title: "健身", start: d("2026-10-05 07:00"),
                            end: d("2026-10-05 08:00"), repeatRule: .weekly([2, 4]))
        let range = DateInterval(start: d("2026-10-12"), end: d("2026-10-19"))
        let occ = Recurrence.occurrences(of: item, in: range, calendar: cal)
        #expect(occ.map { cal.component(.day, from: $0.start) } == [12, 14])
        #expect(occ[0].end == d("2026-10-12 08:00"))
        #expect(Set(occ.map(\.id)).count == 2)
    }

    @Test func monthlyClampsToMonthEnd() {
        let item = LifeItem(fileURL: file, kind: .deadline, title: "房租", start: d("2026-10-31 12:00"), repeatRule: .monthly(31))
        let occ = Recurrence.occurrences(of: item, in: DateInterval(start: d("2026-11-01"), end: d("2026-12-01")), calendar: cal)
        #expect(occ.count == 1 && cal.component(.day, from: occ[0].start) == 30)
    }

    @Test func respectsRepeatUntilAndSingleItems() {
        let item = LifeItem(fileURL: file, kind: .event, title: "x", start: d("2026-10-01 09:00"),
                            repeatRule: .daily, repeatUntil: d("2026-10-03"))
        #expect(Recurrence.occurrences(of: item, in: DateInterval(start: d("2026-10-01"), end: d("2026-10-10")), calendar: cal).count == 3)
        let single = LifeItem(fileURL: file, kind: .window, title: "w", start: d("2026-10-01"), end: d("2026-10-20 23:59"))
        #expect(Recurrence.occurrences(of: single, in: DateInterval(start: d("2026-10-10"), end: d("2026-10-11")), calendar: cal).count == 1)
    }
}

@Suite struct ClassScheduleTests {
    @Test func parsesCommonFormats() {
        let a = ClassSchedule.parse("Tue/Thu 2:00–2:50pm")
        #expect(a == [ClassMeeting(weekdays: [3, 5], startMinute: 14 * 60, endMinute: 14 * 60 + 50, sections: [])])
        let b = ClassSchedule.parse("Mon/Wed 14:00–15:15")[0]
        #expect(b.weekdays == [2, 4] && b.startMinute == 840 && b.endMinute == 915)
        let c = ClassSchedule.parse("Tue/Thu 9:30–10:45am")[0]
        #expect(c.startMinute == 570)
        let e = ClassSchedule.parse("TR 11:00-12:15pm")[0]
        #expect(e.weekdays == [3, 5] && e.startMinute == 660 && e.endMinute == 735)
        #expect(ClassSchedule.parse("完全异步（无固定上课时间）").isEmpty)
    }

    @Test func picksSection() {
        let s = "MWF 9:30–10:20 (A/GR) · MWF 11:00–11:50 (B)"
        #expect(ClassSchedule.parse(s).count == 2)
        let mine = ClassSchedule.meetings(s, section: "B")
        #expect(mine.count == 1 && mine[0].startMinute == 660 && mine[0].weekdays == [2, 4, 6])
        #expect(ClassSchedule.meetings(s, section: nil).count == 2)
    }
}

@Suite struct CourseOSBridgeTests {
    let table = """
    | id | course | title | event_kind | when | estimated_workload | category | submitted | status |
    |---|---|---|---|---|---|---|---|---|
    | a | CS-1331 | Exam 02 | exam | 2026-10-14 | 6h | notice |  | pending |
    | b | CS-1331 | HW \\| 2 | due | 2026-10-14 20:00 | 4h | task | true | pending |
    | c | APPH | Cleanup | other | 2026-10-11 09:00 |  | optional |  | ignored |
    """

    @Test func parsesTable() {
        let rows = CourseOSBridge.parseTable(table, calendar: cal)
        #expect(rows.count == 3)
        #expect(rows[1].title == "HW | 2" && rows[1].done && rows[1].workloadHours == 4)
        #expect(!rows[0].hasTime && rows[2].ignored)
    }

    @Test func buildsOccurrencesRespectingLayers() {
        let snap = CourseOSSnapshot(
            semesterRoot: file,
            courses: [.init(id: "CS-1331", directory: "", schedule: "MWF 9:30–10:20 (A/GR) · MWF 11:00–11:50 (B)", location: "")],
            entries: CourseOSBridge.parseTable(table, calendar: cal), subtasks: [])
        var config = LifeConfig()
        config.courseos.sections = ["CS-1331": "B"]
        config.courseos.classesUntil = "2026-10-13"
        let range = DateInterval(start: d("2026-10-12"), end: d("2026-10-19"))
        let occ = CourseOSBridge.occurrences(snap, in: range, config: config, calendar: cal)
        let classes = occ.filter { $0.style == .classSession }
        #expect(classes.count == 1 && cal.component(.hour, from: classes[0].start) == 11)
        #expect(occ.contains { $0.style == .courseExam && $0.allDay })
        #expect(!occ.contains { $0.courseItemID == "c" })
        config.layers.courseDeadlines = false
        #expect(CourseOSBridge.occurrences(snap, in: range, config: config, calendar: cal).allSatisfy { $0.style == .classSession })
    }
}

@Suite struct InsightsTests {
    @Test func spreadsCourseworkBeforeDue() {
        let due = Occurrence(id: "x", style: .courseDue, title: "HW", start: d("2026-10-16 09:00"), workloadHours: 6)
        let loads = Insights.loads([due], calendar: cal)
        // 上午截止：不算当天，摊到 14、15 日
        #expect(loads[d("2026-10-15")]?.courseworkHours == 3)
        #expect(loads[d("2026-10-14")]?.courseworkHours == 3)
        #expect(loads[d("2026-10-16")] == nil)
    }

    @Test func hintsOverlapAndExamEve() {
        let dinner = Occurrence(id: "d", style: .event, title: "吃饭", start: d("2026-10-13 19:00"), end: d("2026-10-13 21:00"), itemID: "d")
        let review = Occurrence(id: "r", style: .event, title: "复习课", start: d("2026-10-13 20:00"), end: d("2026-10-13 22:00"))
        let exam = Occurrence(id: "e", style: .courseExam, title: "Exam 02", subtitle: "CS-1331", start: d("2026-10-14"), allDay: true)
        let hints = Insights.hints(for: dinner, among: [dinner, review, exam], loads: [:], calendar: cal)
        #expect(hints.count == 2)
        #expect(hints.contains { $0.text.contains("复习课") })
        #expect(hints.contains { $0.text.contains("第二天有考试") })
    }

    @Test func freeSlotsPreferLightDays() {
        let busy = Occurrence(id: "c", style: .classSession, title: "c", start: d("2026-10-15 09:00"), end: d("2026-10-15 20:30"))
        let loads = Insights.loads([busy], calendar: cal)
        let slots = Insights.freeSlots(from: d("2026-10-15 08:00"), until: d("2026-10-16"), hours: 1, among: [busy],
                                       loads: loads, calendar: cal)
        #expect(slots.count == 1)  // 15 日 20:30 之后只剩 30 分钟，不够
        #expect(slots[0].interval.start == d("2026-10-16 09:00"))
    }

    @Test func upcomingShowsOnlyWithinReminder() {
        let now = d("2026-10-15 10:00")
        let soon = LifeItem(fileURL: URL(fileURLWithPath: "/a"), kind: .deadline, title: "交税", start: d("2026-10-17 12:00"))
        let later = LifeItem(fileURL: URL(fileURLWithPath: "/b"), kind: .deadline, title: "退租", start: d("2026-11-30 12:00"))
        let done = LifeItem(fileURL: URL(fileURLWithPath: "/c"), kind: .deadline, title: "x", start: d("2026-10-16 12:00"), done: true)
        let ending = LifeItem(fileURL: URL(fileURLWithPath: "/d"), kind: .window, title: "买菜", start: d("2026-10-12"), end: d("2026-10-16 23:59"))
        let titles = Insights.upcoming([soon, later, done, ending], now: now, calendar: cal).map(\.title)
        #expect(titles == ["买菜", "交税"])
    }
}

@Suite struct VaultStoreTests {
    @Test func createMoveAndInbox() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lifeos-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VaultStore(root: root)
        let url = try store.createItem(kind: .event, title: "看牙", start: d("2026-10-20 14:00"),
                                       end: d("2026-10-20 15:00"), startHasTime: true, location: "Midtown", calendar: cal)
        let url2 = try store.createItem(kind: .event, title: "看牙", start: d("2026-10-20 16:00"), end: nil, startHasTime: true, calendar: cal)
        #expect(url != url2)
        let item = store.loadItems(calendar: cal).first { $0.fileURL.lastPathComponent == url.lastPathComponent }!
        try store.move(item, to: d("2026-10-21 09:00"), calendar: cal)
        let moved = store.loadItems(calendar: cal).first { $0.fileURL.lastPathComponent == url.lastPathComponent }!
        #expect(moved.start == d("2026-10-21 09:00") && moved.end == d("2026-10-21 10:00") && moved.location == "Midtown")

        try store.appendInbox("下周三前去银行改地址")
        try store.appendInbox("买牙膏")
        #expect(store.inboxLines() == ["下周三前去银行改地址", "买牙膏"])
        try store.removeInbox("买牙膏")
        #expect(store.inboxLines() == ["下周三前去银行改地址"])
    }
}
