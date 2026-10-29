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

@Suite struct LifeConfigTests {
    @Test func semesterPathResolvesAbsoluteAndRelative() {
        let vault = URL(fileURLWithPath: "/Users/a/Desktop/SharedDocs/Obsidian/LifeOS")
        var link = LifeConfig.CourseOSLink()
        link.semester = ""
        #expect(link.resolvedSemesterURL(vault: vault) == nil)

        link.semester = "/Users/a/Desktop/SharedDocs/Obsidian/GT-semseters/2026Fall"
        #expect(link.resolvedSemesterURL(vault: vault)?.path == link.semester)

        // 兄弟目录：换一台电脑、换用户名也该解析到同样的相对位置
        link.semester = "../GT-semseters/2026Fall"
        let vaultOnOtherMac = URL(fileURLWithPath: "/Users/b/Desktop/SharedDocs/Obsidian/LifeOS")
        #expect(link.resolvedSemesterURL(vault: vaultOnOtherMac)?.path
                == "/Users/b/Desktop/SharedDocs/Obsidian/GT-semseters/2026Fall")
    }

    @Test func relativePathFindsCommonAncestor() {
        let vault = URL(fileURLWithPath: "/Users/a/Desktop/SharedDocs/Obsidian/LifeOS")
        let semester = URL(fileURLWithPath: "/Users/a/Desktop/SharedDocs/Obsidian/GT-semseters/2026Fall")
        #expect(LifeConfig.CourseOSLink.relativePath(from: vault, to: semester) == "../GT-semseters/2026Fall")

        // 没有共同上级（不同磁盘）就退回 nil，调用方存绝对路径
        let elsewhere = URL(fileURLWithPath: "/Volumes/External/GT-semseters/2026Fall")
        #expect(LifeConfig.CourseOSLink.relativePath(from: vault, to: elsewhere) == nil)
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

@Suite struct HealthTests {
    @Test func parsesTargetsAndMeals() {
        let targets = HealthStore.parseTargets("---\ntype: health-targets\nkcal: 2500\nprotein: 130 g\ncarbs: 330\nfat: 60\n---\n")!
        #expect(targets == Nutrition(kcal: 2500, protein: 130, carbs: 330, fat: 60))
        let text = """
        ---
        type: health-diet
        date: 2026-10-22
        ---
        # 2026-10-22 饮食

        | 时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪 |
        |---|---|---|---|---|---|
        | 08:30 | 两个鸡蛋、一碗燕麦 | ~390 | 20 g | 45 | 14 |
        | 12:40 | Chick-fil-A 烤鸡块 12 块 |  |  |  |  |

        ## 建议
        | 不是 | 饮食表 |
        |---|---|
        | x | y |
        """
        let meals = HealthStore.parseMeals(text)
        #expect(meals.count == 2)
        #expect(meals[0].nutrition == Nutrition(kcal: 390, protein: 20, carbs: 45, fat: 14))
        #expect(!meals[1].isEstimated && meals[1].text == "Chick-fil-A 烤鸡块 12 块")
        let day = DietDay(date: d("2026-10-22"), meals: meals)
        #expect(day.total.kcal == 390 && day.pendingCount == 1)
    }

    @Test func periodsAndSummaries() {
        // 2026-10-29 是周四；和 App 一样周一起
        var cal = cal
        cal.firstWeekday = 2
        let week = HealthPeriod(scale: .week, anchor: d("2026-10-29"))
        let days = week.days(calendar: cal)
        #expect(days.count == 7 && cal.isDate(days[0], inSameDayAs: d("2026-10-26")))
        #expect(HealthPeriod(scale: .month, anchor: d("2026-10-29")).days(calendar: cal).count == 31)
        #expect(HealthPeriod(scale: .day, anchor: d("2026-10-29")).days(calendar: cal).count == 1)
        #expect(cal.isDate(week.stepped(-1, calendar: cal).days(calendar: cal)[0], inSameDayAs: d("2026-10-19")))
        let nov = HealthPeriod(scale: .month, anchor: d("2026-10-29")).stepped(1, calendar: cal)
        #expect(nov.days(calendar: cal).count == 30)

        var s = HealthSnapshot.empty
        s.sleep = [
            SleepNight(date: d("2026-10-27"), bedtime: "23:30", wake: "07:30", minutes: 480),
            SleepNight(date: d("2026-10-28"), bedtime: "00:30", wake: "08:30", minutes: 480),
            SleepNight(date: d("2026-10-30"), bedtime: nil, wake: "08:00", minutes: nil),
            SleepNight(date: d("2026-11-02"), bedtime: "01:00", wake: "09:00", minutes: 480),
        ]
        let sum = s.sleepSummary(in: week.interval(calendar: cal))
        #expect(sum.nights.count == 3 && sum.averageMinutes == 480)
        // 23:30 和 00:30 平均是 00:00，不是中午
        #expect(sum.averageBedtime == "00:00")
        #expect(sum.averageWake == "08:00")
        #expect(HealthSnapshot.bedtimeHour("00:30") == 24.5 && HealthSnapshot.bedtimeHour("23:30") == 23.5)

        let url = URL(fileURLWithPath: "/tmp/x.md")
        s.sessions = [
            HealthSession(fileURL: url, date: d("2026-10-26"), kind: .strength, title: "上肢", volume: 3000, note: ""),
            HealthSession(fileURL: url, date: d("2026-10-26"), kind: .run, title: "跑", distanceKm: 2, minutes: 14, note: ""),
            HealthSession(fileURL: url, date: d("2026-10-27"), kind: .strength, title: "下肢", volume: 5000, note: ""),
            HealthSession(fileURL: url, date: d("2026-10-20"), kind: .strength, title: "上周", volume: 999, note: ""),
        ]
        let f = s.fitnessSummary(in: week.interval(calendar: cal), calendar: cal)
        #expect(f.sessions.count == 3 && f.activeDays == 2 && f.strengthCount == 2 && f.runCount == 1)
        #expect(f.volume == 8000 && f.runKm == 2 && f.pace == 7)

        let avg = Nutrition.average([Nutrition(kcal: 2000, micros: ["sodium": 3000]), Nutrition(kcal: 3000)])
        #expect(avg?.kcal == 2500 && avg?.micros["sodium"] == 3000)
        #expect(Nutrition.average([]) == nil)
    }

    @Test func recipesShoppingAndPrep() throws {
        let text = """
        ---
        type: recipe
        name: 孜然猪肉土豆卷
        meal: 备餐
        batch: 8
        kcal: 850
        protein: 34
        carbs: 80
        fat: 38
        sodium: 650
        ---
        # 孜然猪肉土豆卷

        ## 材料
        | 材料 | 一份用量 | 在哪买 |
        |---|---|---|
        | 卷饼皮 | 1 张 | 超市 |
        | 猪绞肉 | 1/4 包（4 oz） | Weee |
        | 土豆 | 100 g | 超市 |
        | 孜然粉 | 适量 | 家里有 |
        | 青椒 | 适量 | 超市 |

        ## 做法
        1. 米饭晾凉
        2、肉先炒

        ## 变化
        换成鸡肉碎更瘦。
        """
        let url = URL(fileURLWithPath: "/tmp/食谱/孜然猪肉土豆卷.md")
        let r = try #require(HealthStore.parseRecipe(text, url: url))
        #expect(r.name == "孜然猪肉土豆卷" && r.meal == "备餐" && r.batch == 8)
        #expect(r.nutrition?.kcal == 850 && r.nutrition?.micros["sodium"] == 650)
        #expect(r.ingredients.count == 5 && r.ingredients[1].quantity?.value == 0.25 && r.ingredients[1].quantity?.unit == "包")
        #expect(r.steps == ["米饭晾凉", "肉先炒"] && r.notes.contains("鸡肉碎"))
        #expect(HealthStore.parseRecipe("---\ntype: note\n---\n", url: url) == nil)

        var other = r
        other.name = "西红柿炒蛋卷"
        other.ingredients = [Ingredient(name: "土豆", amount: "50 g", store: "超市"), Ingredient(name: "鸡蛋", amount: "2 个", store: "超市")]
        let items = ShoppingList.items(for: [(r, 4), (other, 2)])
        #expect(items.map(\.text).contains("土豆 500 g（孜然猪肉土豆卷 ×4、西红柿炒蛋卷 ×2）"))
        #expect(items.map(\.text).contains("猪绞肉 1 包（孜然猪肉土豆卷 ×4）"))
        #expect(items.map(\.text).contains("青椒 适量（孜然猪肉土豆卷 ×4）"))
        #expect(!items.contains { $0.text.hasPrefix("孜然粉") })
        #expect(Set(items.map(\.store)) == ["超市", "Weee"])

        var list = ShoppingList.adding(items, to: nil)
        list = ShoppingList.adding([ShoppingItem(store: "Amazon", text: "链条油", done: false)] + items, to: list)
        var parsed = ShoppingList.parse(list)
        #expect(parsed.count == items.count + 1)
        list = ShoppingList.toggling(parsed.first { $0.text.hasPrefix("土豆") }!, in: list)
        parsed = ShoppingList.parse(list)
        #expect(parsed.first { $0.text.hasPrefix("土豆") }?.done == true)
        list = ShoppingList.clearingDone(list)
        parsed = ShoppingList.parse(list)
        #expect(!parsed.contains { $0.text.hasPrefix("土豆") } && parsed.contains { $0.store == "Amazon" })
        // 段清空了标题也删
        for i in parsed where i.store == "Weee" { list = ShoppingList.toggling(i, in: list) }
        #expect(!ShoppingList.clearingDone(list).contains("## Weee"))

        let fridge = PrepBatch(made: d("2026-11-01"), name: "孜然猪肉土豆卷", count: 4, left: 4, place: "冷藏",
                               useBy: PrepBatch.defaultUseBy(made: d("2026-11-01"), place: "冷藏", calendar: cal))
        var freezer = fridge
        freezer.place = "冷冻"
        freezer.useBy = PrepBatch.defaultUseBy(made: d("2026-11-01"), place: "冷冻", calendar: cal)
        var prep = MealPrep.adding(fridge, to: nil, calendar: cal)
        prep = MealPrep.adding(freezer, to: prep, calendar: cal)
        var batches = MealPrep.parse(prep, calendar: cal)
        #expect(batches.count == 2 && batches[0].useBy == d("2026-11-04") && batches[1].useBy == d("2026-12-31"))
        prep = MealPrep.settingLeft(batches[0], to: 3, in: prep, calendar: cal)
        batches = MealPrep.parse(prep, calendar: cal)
        #expect(batches[0].left == 3 && batches[1].left == 4)

        // 吃一份：按表头把营养填进饮食表
        let row = HealthStore.mealRow(header: HealthStore.tableColumns, time: "12:30", text: "孜然猪肉土豆卷 ×1", nutrition: r.nutrition)
        #expect(row == "| 12:30 | 孜然猪肉土豆卷 ×1 | 850 | 34 | 80 | 38 | 650 |  |  |  |  |  |  |  |")
        #expect(HealthStore.parseMeals("| 时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪 | 钠 |\n|---|---|---|---|---|---|---|\n" + row)
            .first?.nutrition?.micros["sodium"] == 650)
    }

    @Test func cumulativeMonthSpending() {
        func e(_ day: String, _ amount: Double, _ kind: LedgerEntry.Kind = .expense) -> LedgerEntry {
            LedgerEntry(id: day + "\(amount)", date: d(day), text: "", category: "吃", amount: amount, kind: kind, account: "")
        }
        let f = FinanceSnapshot(entries: [e("2026-10-02", 10), e("2026-10-02", 5), e("2026-10-05", 20), e("2026-10-06", 99, .income),
                                          e("2026-09-30", 7)], accounts: [], subscriptions: [], budget: ["吃": 300, "玩": 50])
        let all = f.cumulativeSpending(inMonthOf: d("2026-10-15"), calendar: cal)
        #expect(all.count == 31 && all[0].total == 0 && all[1].total == 15 && all[4].total == 35 && all[30].total == 35)
        #expect(f.cumulativeSpending(inMonthOf: d("2026-10-15"), through: d("2026-10-05"), calendar: cal).count == 5)
        #expect(f.totalBudget == 350)
    }

    @Test func weightsPlanAndSleepComparison() throws {
        let text = """
        ---
        type: health-weight
        ---
        | 日期 | 体重（lb） | 备注 |
        |---|---|---|
        | 2026-10-22 | 144 lb（65.3 kg） | 起点 |
        | 2026-10-29 | 65.8 kg | |
        | 2026-11-05 | 146.2 | |
        | 不是日期 | 1 | |
        """
        let w = HealthStore.parseWeights(text, calendar: cal)
        #expect(w.count == 3 && w[0].lb == 144 && w[0].note == "起点")
        #expect(abs(w[1].lb - 145.06) < 0.01)
        #expect(HealthStore.parseWeightInput("65.8 kg").map { abs($0 - 145.06) < 0.01 } == true)
        #expect(HealthStore.parseWeightInput("145磅") == 145 && HealthStore.parseWeightInput("重") == nil)

        let plan = HealthStore.parseWeightPlan("---\nsince: 2026-10-29\nweight_gain_min: 0.5\nweight_gain_max: 1\n---\n", calendar: cal)
        #expect(plan?.minKgPerMonth == 0.5 && plan?.maxKgPerMonth == 1)
        var s = HealthSnapshot.empty
        s.weights = w
        s.weightPlan = plan
        // 起点：目标生效那天（含）之前最近一次
        #expect(s.weightBaseline?.date == d("2026-10-29"))
        let band = plan!.band(from: s.weightBaseline!, at: d("2026-10-29").addingTimeInterval(30.44 * 86400))
        #expect(abs(band.low - (w[1].lb + 0.5 / WeightEntry.kgPerLb)) < 0.01 && abs(band.high - (w[1].lb + 1 / WeightEntry.kgPerLb)) < 0.01)
        #expect(s.weightChange(days: 7, until: d("2026-11-05"), calendar: cal).map { abs($0 - 1.14) < 0.01 } == true)
        #expect(HealthStore.parseWeightPlan("---\nweight_gain_min: -0.5\nweight_gain_max: -1\n---\n", calendar: cal)?.minKgPerMonth == -0.5)

        // 体重写入：同一天替换、按日期插入
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vault) }
        let store = HealthStore(vault: vault)
        #expect(try store.recordWeight(day: d("2026-11-05"), value: "146", calendar: cal) == nil)
        try store.recordWeight(day: d("2026-10-29"), value: "65.8 kg", calendar: cal)
        try store.recordWeight(day: d("2026-11-05"), value: "146.4", calendar: cal)
        #expect(store.loadWeights(calendar: cal).map(\.lb) == [145.1, 146.4])
        #expect(throws: HealthStore.WeightEntryError.badWeight("很重")) { try store.recordWeight(day: d("2026-11-06"), value: "很重", calendar: cal) }

        let nights = [
            SleepNight(date: d("2026-10-27"), bedtime: nil, wake: nil, minutes: 420),  // 10/26 练了
            SleepNight(date: d("2026-10-28"), bedtime: nil, wake: nil, minutes: 480),  // 10/27 练了
            SleepNight(date: d("2026-10-29"), bedtime: nil, wake: nil, minutes: 540),  // 10/28 没练；这天考试
            SleepNight(date: d("2026-10-30"), bedtime: nil, wake: "08:00", minutes: nil),
        ]
        let c = SleepComparison.compute(nights, trainingDays: [d("2026-10-26"), d("2026-10-27")],
                                        examDays: [d("2026-10-29")], calendar: cal)
        #expect(c.afterTraining == 450 && c.afterTrainingCount == 2)
        #expect(c.afterRest == 540 && c.afterRestCount == 1)
        #expect(c.beforeExam == 540 && c.beforeExamCount == 1)
    }

    @Test func completeDaysAndTargetsAtTheTime() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vault) }
        let store = HealthStore(vault: vault)
        let fm = FileManager.default
        try fm.createDirectory(at: store.dietDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: store.targetHistoryDir, withIntermediateDirectories: true)
        try "---\ntype: health-targets\nkcal: 2800\nprotein: 130\nsince: 2026-10-29\n---\n"
            .write(to: store.targetsURL, atomically: true, encoding: .utf8)
        try "---\ntype: health-targets\nkcal: 2500\nprotein: 130\nsince: 2026-10-22\n---\n"
            .write(to: store.targetHistoryDir.appendingPathComponent("2026-10-22.md"), atomically: true, encoding: .utf8)
        func day(_ date: String, complete: String? = nil, kcal: Int?) throws {
            let flag = complete.map { "complete: \($0)\n" } ?? ""
            let row = kcal.map { "| 12:00 | 饭 | \($0) | 30 | 1 | 1 |" } ?? "| 12:00 | 饭 |  |  |  |  |"
            try "---\ntype: health-diet\ndate: \(date)\n\(flag)---\n| 时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪 |\n|---|---|---|---|---|---|\n\(row)\n"
                .write(to: store.dietURL(d(date), calendar: cal), atomically: true, encoding: .utf8)
        }
        try day("2026-10-26", kcal: 2400)                     // 没写 = 过去的日子算记全
        try day("2026-10-27", complete: "false", kcal: 900)   // 只记了一半
        try day("2026-10-28", kcal: nil)                      // 只有待估算的，不算
        try day("2026-10-29", kcal: 1200)                     // 今天还在吃，不算
        try day("2026-10-30", complete: "true", kcal: 2600)   // 写了记全，就算（哪怕是“今天”）

        let s = store.load(calendar: cal)
        let today = d("2026-10-29")
        #expect(s.completeDays(last: 7, until: today, today: today, calendar: cal).map(\.total.kcal) == [2400])
        #expect(s.day(d("2026-10-30"), calendar: cal).isComplete(today: d("2026-10-30"), calendar: cal))

        #expect(s.targetHistory.map(\.targets.kcal) == [2500, 2800])
        #expect(s.targets(on: d("2026-10-28"), calendar: cal)?.kcal == 2500)
        #expect(s.targets(on: d("2026-10-29"), calendar: cal)?.kcal == 2800)
        // 比最早一份还早：用最早那份
        #expect(s.targets(on: d("2026-10-01"), calendar: cal)?.kcal == 2500)
        // 没有历史：退回现在的目标
        var bare = HealthSnapshot.empty
        bare.targets = Nutrition(kcal: 2000)
        #expect(bare.targets(on: today, calendar: cal)?.kcal == 2000)
    }

    @Test func appendsRowAfterTableAndCreatesFile() {
        let text = "---\ntype: health-diet\n---\n\(HealthStore.tableHeader)\n| 08:30 | 鸡蛋 | 150 | 12 | 1 | 10 |\n\n## 建议\n多吃蛋白\n"
        let out = HealthStore.insertRow("| 12:00 | 鸡块 |  |  |  |  |", into: text)
        #expect(out.contains("| 08:30 | 鸡蛋 | 150 | 12 | 1 | 10 |\n| 12:00 | 鸡块 |  |  |  |  |\n\n## 建议"))
        let fresh = HealthStore.newDayFile(d("2026-10-22"), calendar: cal, firstRow: "| 09:00 | 燕麦 |  |  |  |  |")
        #expect(HealthStore.parseMeals(fresh).count == 1)
        #expect(Frontmatter.parse(fresh).fields["date"] == "2026-10-22")
    }

    @Test func parsesTestsInFileOrderAndTrainingTable() {
        let t = HealthStore.parseTest("---\ntype: health-test\ndate: 2026-10-22\ntitle: 起点\nweight: 65 kg\npushups: 25\nmile:\n---\n",
                                      fileURL: file, calendar: cal)!
        #expect(t.fields.map(\.key) == ["weight", "pushups"])
        let body = "## 报名\n文字\n\n## 练什么（前 4 周）\n| 动作 | 组×次 |\n|---|---|\n| 卧推 | 3×8 |\n| 肩推 | 3×10 |\n\n## 时间\n…"
        let plan = TrainingPlan.firstTable(in: body)!
        #expect(plan.heading.hasPrefix("练什么") && plan.rows.count == 2 && plan.rows[0] == ["卧推", "3×8"])
        let item = LifeItem.parse(text: "---\ntitle: 力量\nstart: 2026-10-23 12:00\nplugin: Health\n---\n", fileURL: file, calendar: cal)!
        #expect(item.plugin == "health")
        let weeks = [["10/22 那一周", "2 km"], ["10/27 那一周", "2.5 km"], ["11/3 那一周", "3 km"]]
        #expect(TrainingPlan.rows(weeks, for: d("2026-10-29 11:00"), calendar: cal) == [["10/27 那一周", "2.5 km"]])
        #expect(TrainingPlan.rows(weeks, for: d("2026-10-22 11:00"), calendar: cal) == [["10/22 那一周", "2 km"]])
        #expect(TrainingPlan.rows(plan.rows, for: d("2026-10-29"), calendar: cal) == plan.rows)
    }

    @Test func configPluginsDefaultOff() throws {
        let old = try JSONDecoder().decode(LifeConfig.self, from: Data("{\"layers\":{\"classes\":true,\"courseDeadlines\":true,\"courseOptional\":false}}".utf8))
        #expect(old.plugins.health == false)
        let on = try JSONDecoder().decode(LifeConfig.self, from: Data("{\"plugins\":{\"health\":true}}".utf8))
        #expect(on.plugins.health && !on.plugins.things && !on.plugins.finance)
    }

    @Test func bodySessionsAndWeekStats() {
        let body = HealthStore.parseBody("---\ntype: health-body\nupdated: 2026-10-22\nheight: 175 cm\nweight: 65 kg\nbench: 65 lb×8\n---\n", calendar: cal)
        #expect(body.fields.map(\.key) == ["height", "weight", "bench"] && HealthBody.group("bench") == "力量")
        let run = HealthStore.parseSession("---\ntype: health-session\ndate: 2026-10-22\nkind: run\ntitle: 轻松跑\ndistance: 2.1 km\nduration: 13:20\n---\n感觉不错\n",
                                           fileURL: file, calendar: cal)!
        #expect(run.distanceKm == 2.1 && abs(run.pace! - (13 + 1.0/3) / 2.1) < 1e-9 && run.note == "感觉不错")
        let lift = HealthStore.parseSession("---\ntype: health-session\ndate: 2026-10-28\nkind: strength\n---\n| 动作 | 重量 | 组×次 |\n|---|---|---|\n| 卧推 | 65 lb | 3×8 |\n| 俯卧撑 |  | 2×15 |\n",
                                            fileURL: file, calendar: cal)!
        #expect(lift.volume == 1560.0)
        let weeks = WeekStats.compute([run, lift], calendar: cal)
        #expect(weeks.count == 2 && weeks[0].runKm == 2.1 && weeks[1].volume == 1560 && weeks[1].pace == nil)
        #expect(HealthFormat.minutesText(6.5) == "6:30")
    }
}

@Suite struct ThingsTests {
    private let root = URL(fileURLWithPath: "/tmp/物品")

    @Test func intervalsAndConsumables() {
        #expect(Interval.parse("45天") == Interval(value: 45, unit: .day))
        #expect(Interval.parse("2w") == Interval(value: 2, unit: .weekOfYear))
        #expect(Interval.parse("每 500 km") == nil)
        let text = "---\ntype: thing\nname: 洗衣液\ncategory: 耗材\nlasts: 45天\nrestocked: 2026-10-01\nprice: 12.99 USD\n---\n"
        let t = Thing.parse(text: text, fileURL: root.appendingPathComponent("洗衣液.md"), root: root, calendar: cal)!
        #expect(t.isConsumable && t.price == 12.99 && t.currency == "USD")
        #expect(DateText.format(t.nextRestock(calendar: cal)!, withTime: false, calendar: cal) == "2026-11-15")
        let occ = ThingCalendar.occurrences([t], in: DateInterval(start: d("2026-11-01"), duration: 30 * 86400), calendar: cal)
        #expect(occ.count == 1 && occ[0].style == .window && occ[0].title == "补货：洗衣液")
    }

    @Test func detailedMaintenance() {
        let text = """
        ---
        type: thing
        name: 自行车
        category: 交通
        maintenance: detailed
        photo: 照片/bike.jpg
        return_until: 2026-11-05
        ---
        ## 规格
        | 部件 | 型号 |
        |---|---|
        | 轮胎 | 700×28c |

        ## 保养计划
        | 项目 | 间隔 | 上次 | 备注 |
        |---|---|---|---|
        | 链条上油 | 每 2 周 | 2026-10-10 | |
        | 换刹车片 | 每 500 km | | 看磨损 |

        ## 保养记录
        | 日期 | 做了什么 | 里程 | 花费 | 在哪做 |
        |---|---|---|---|---|
        | 2026-09-01 | 买车时调校 | 0 | 0 | 店里 |
        | 2026-10-10 | 链条上油 | 120 km | 8 | 自己 |
        """
        let t = Thing.parse(text: text, fileURL: root.appendingPathComponent("自行车.md"), root: root, calendar: cal)!
        #expect(t.detailed && t.photo?.lastPathComponent == "bike.jpg" && t.specs == [["轮胎", "700×28c"]])
        let tasks = t.maintenanceTasks(calendar: cal)
        #expect(tasks.count == 2 && DateText.format(tasks[0].next!, withTime: false, calendar: cal) == "2026-10-24")
        #expect(tasks[1].next == nil && tasks[1].everyText == "每 500 km")
        let log = t.maintenanceLog(calendar: cal)
        #expect(log.first?.what == "链条上油" && log.compactMap(\.cost).reduce(0, +) == 8)
        let occ = ThingCalendar.occurrences([t], in: DateInterval(start: d("2026-10-15"), duration: 30 * 86400), calendar: cal)
        #expect(Set(occ.map(\.title)) == ["退货截止：自行车", "保养：自行车 · 链条上油"])
    }
}


@Suite struct FinanceTests {
    @Test func ledgerAccountsSubscriptions() {
        let ledger = """
        ---
        type: ledger
        month: 2026-10
        ---
        | 日期 | 说明 | 类别 | 金额 | 收支 | 账户 |
        |---|---|---|---|---|---|
        | 2026-10-22 | Chick-fil-A | 餐饮 | 12.47 | 支出 | 借记卡 |
        | 2026-10-20 | Kroger | 买菜 | $35.10 |  | 借记卡 |
        | 2026-10-01 | 家里打的生活费 | 生活费 | 1500 | 收入 | 借记卡 |
        """
        let es = FinanceStore.parseLedger(ledger, fileID: "2026-10.md", calendar: cal)
        #expect(es.count == 3 && es[1].kind == .expense && es[1].amount == 35.10 && es[2].kind == .income)
        let snap = FinanceSnapshot(entries: es, accounts: [], subscriptions: [], budget: [:])
        let cats = snap.spendingByCategory(inMonthOf: d("2026-10-15"), calendar: cal)
        #expect(cats.first?.category == "买菜" && cats.count == 2)
        let months = snap.monthlyTotals(endingAt: d("2026-10-15"), months: 3, calendar: cal)
        #expect(months.count == 3 && months[2].income == 1500 && months[0].expense == 0)

        let accounts = FinanceStore.parseAccounts("| 账户 | 类型 | 余额 | 更新日期 |\n|---|---|---|---|\n| 借记卡 | 支票 | 2,340.55 | 2026-10-22 |\n| 信用卡 | 信用 | -210 | 2026-10-22 |\n", calendar: cal)
        #expect(accounts.count == 2 && accounts[0].balance == 2340.55 && accounts[1].balance == -210)

        let subs = FinanceStore.parseSubscriptions("| 名称 | 金额 | 周期 | 下次扣款 | 账户 | 类别 |\n|---|---|---|---|---|---|\n| Claude | 20 | 每月 | 2026-11-05 | 信用卡 | 订阅 |\n| iCloud | 35.88 | 每年 | 2027-03-01 | 信用卡 | |\n", calendar: cal)
        #expect(subs.count == 2 && subs[0].monthly == 20 && abs(subs[1].monthly! - 2.99) < 0.001)
        let charges = subs[0].charges(in: DateInterval(start: d("2026-10-01"), end: d("2027-01-01")), calendar: cal)
        #expect(charges.map { DateText.format($0, withTime: false, calendar: cal) } == ["2026-10-05", "2026-11-05", "2026-12-05"])
        #expect(FinanceStore.parseBudget("| 类别 | 每月 |\n|---|---|\n| 餐饮 | 400 |\n") == ["餐饮": 400])
    }
}

@Suite struct TravelTests {
    private let root = URL(fileURLWithPath: "/tmp/出行")

    @Test func multiDayTripParsesAndToggles() throws {
        let text = """
        ---
        type: trip
        title: 感恩节佛罗里达
        route: Atlanta → Orlando → Miami
        start: 2026-11-25
        end: 2026-11-28
        status: 规划中
        ---
        # 感恩节佛罗里达

        ## 每天
        ### 第 1 天 · 2026-11-25 · Orlando
        | 时间 | 安排 | 地点 | 备注 |
        |---|---|---|---|
        | 08:00–15:00 | 开车去 Orlando | I-75 | |
        | 晚上 | 吃饭 | | |

        ### 第 2 天 · 2026-11-26 · Orlando
        | 时间 | 安排 | 地点 | 备注 |
        |---|---|---|---|
        | 10:00 | 主题公园 | | |

        ## 住宿
        | 入住 | 退房 | 城市 | 名称 | 地址 | 确认号 | 价格 | 免费取消截止 |
        |---|---|---|---|---|---|---|---|
        | 2026-11-25 | 2026-11-27 | Orlando | 某酒店 | | | $240 | 2026-11-20 |

        ## 要带
        - [ ] 驾照
        - [x] 充电器

        ## 期限
        | 截止 | 要做的事 |
        |---|---|
        | 2026-11-10 | 订酒店 |

        ## 预算
        | 项目 | 预计 | 实际 |
        |---|---|---|
        | 住宿 | 240 | |
        | 油费 | 80 | 75 |
        """
        let trip = Trip.parse(text: text, fileURL: root.appendingPathComponent("t.md"), root: root, calendar: cal)!
        #expect(trip.dayCount(calendar: cal) == 4 && trip.days.count == 2 && trip.days[0].city == "Orlando")
        #expect(trip.days[0].items[0].start != nil && trip.days[0].items[0].end != nil && trip.days[0].items[1].start == nil)
        #expect(trip.lodging.first?.name == "某酒店" && trip.lodging.first?.freeCancelUntil != nil)
        #expect(trip.deadlines.count == 1 && trip.budget.count == 2 && trip.budget[1].actual == 75)
        #expect(trip.packing.map(\.done) == [false, true])
        let lines = text.components(separatedBy: "\n")
        #expect(lines[trip.packing[0].line].hasSuffix("驾照"))

        let occ = TravelCalendar.occurrences([trip], in: DateInterval(start: d("2026-11-01"), end: d("2026-12-01")), calendar: cal)
        #expect(occ.contains { $0.title == "出行：感恩节佛罗里达" && $0.allDay })
        #expect(occ.contains { $0.title == "开车去 Orlando" } && occ.contains { $0.title == "订酒店" && $0.style == .deadline })
        #expect(occ.contains { $0.title == "免费取消截止：某酒店" })

        // 勾选只改那一行
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("t.md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        let onDisk = Trip.parse(text: text, fileURL: url, root: dir, calendar: cal)!
        try TravelStore(vault: dir).togglePacking(onDisk.packing[0], in: onDisk)
        let after = try String(contentsOf: url, encoding: .utf8)
        #expect(after.contains("- [x] 驾照") && after.replacingOccurrences(of: "- [x] 驾照", with: "- [ ] 驾照") == text)
    }
}

@Suite struct TripShareTests {
    private let text = """
    ---
    type: trip
    title: 测试之旅
    route: Atlanta → Orlando
    start: 2026-11-25
    end: 2026-11-26
    with: 小明
    ---
    ## 每天
    ### 第 1 天 · 2026-11-25 · Orlando
    | 时间 | 安排 | 地点 | 备注 |
    |---|---|---|---|
    | 10:00–12:00 | 逛 <公园> | Lake Eola | |

    ## 交通
    | 日期 | 时间 | 方式 | 从 | 到 | 订单 / 备注 |
    |---|---|---|---|---|---|
    | 2026-11-25 | 08:00 | 开车 | Atlanta | Orlando | 订单 ABC123 |

    ## 住宿
    | 入住 | 退房 | 城市 | 名称 | 地址 | 确认号 | 价格 | 免费取消截止 |
    |---|---|---|---|---|---|---|---|
    | 2026-11-25 | 2026-11-26 | Orlando | 湖边酒店 | 1 Lake St | CONF99 | $120 | |

    ## 地点与须知
    - **Lake Eola**：全天开放

    ## 要带
    - [ ] 驾照

    ## 期限
    | 截止 | 要做的事 |
    |---|---|
    | 2026-11-10 | 订酒店 |
    """

    @Test func privacyFilterAndFormats() {
        let trip = Trip.parse(text: text, fileURL: URL(fileURLWithPath: "/tmp/出行/t.md"), root: URL(fileURLWithPath: "/tmp/出行"), calendar: cal)!
        let plain = TripShare.text(trip, calendar: cal)
        #expect(plain.contains("【测试之旅】") && plain.contains("10:00–12:00  逛 <公园>（Lake Eola）") && plain.contains("住：湖边酒店"))
        #expect(!plain.contains("CONF99") && !plain.contains("1 Lake St") && !plain.contains("ABC123") && !plain.contains("驾照") && !plain.contains("$120"))
        #expect(plain.contains("- Lake Eola：全天开放"))
        let all = TripShare.text(trip, options: .init(prices: true, privateDetails: true, packing: true), calendar: cal)
        #expect(all.contains("CONF99") && all.contains("1 Lake St") && all.contains("ABC123") && all.contains("☐ 驾照") && all.contains("$120"))

        let ics = TripShare.ics(trip, calendar: cal)
        #expect(ics.components(separatedBy: "BEGIN:VEVENT").count - 1 == 3)
        #expect(ics.contains("DTSTART;VALUE=DATE:20261125") && ics.contains("DTEND;VALUE=DATE:20261127"))
        #expect(ics.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(!ics.contains("CONF99"))

        let html = TripShare.html(trip, calendar: cal)
        #expect(html.contains("逛 &lt;公园&gt;") && !html.contains("CONF99") && html.contains("<title>测试之旅</title>"))
    }
}

@Suite struct MicronutrientTests {
    @Test func microColumnsByHeaderAndTargets() {
        let text = """
        ---
        type: health-diet
        date: 2026-10-22
        ---
        | 时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪 | 钠 | 添加糖 | 纤维 | 维D |
        |---|---|---|---|---|---|---|---|---|---|
        | 12:00 | 三明治 | 420 | 29 | 41 | 18 | 1400 | 6 | 1 | 0 |
        | 18:00 | 面 | 455 | 14 | 96 | 2 | 1100 |  | 3.5 | |
        | 20:00 | App 里记的 |  |  |  |  |  |  |  |  |
        """
        let meals = HealthStore.parseMeals(text)
        #expect(meals.count == 3 && meals[2].nutrition == nil)
        let total = DietDay(date: d("2026-10-22"), meals: meals).total
        #expect(total.micros["sodium"] == 2500 && total.micros["fiber"] == 4.5 && total.micros["sugar"] == 6 && total.micros["vitamin_d"] == 0)
        let t = HealthStore.parseTargets("---\nkcal: 2500\nprotein: 130\nsodium: 2300\nfiber: 38\nvitamin_d: 15\n---\n")!
        #expect(t.micros == ["sodium": 2300, "fiber": 38, "vitamin_d": 15])
        #expect(Micronutrient.forHeader("添加糖")?.key == "sugar" && Micronutrient.forHeader("维生素C")?.key == "vitamin_c")
        #expect(HealthStore.tableHeader.hasPrefix("| 时间 | 吃了什么 | 热量 | 蛋白质 | 碳水 | 脂肪 | 钠 |"))
    }
}

@Suite struct WishlistTests {
    @Test func wishlistQuickAddAndMatch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ThingStore(vault: dir)
        #expect(try store.appendWish("充电宝", now: d("2026-10-22"), calendar: cal) == nil)
        try store.appendWish("机械键盘", now: d("2026-10-23"), calendar: cal)
        let wishes = store.loadWishlist(calendar: cal)
        #expect(wishes.map(\.name) == ["充电宝", "机械键盘"] && wishes.allSatisfy(\.isOpen))
        let url = try store.quickAdd("剪刀，厨房第二个抽屉", now: d("2026-10-22"), calendar: cal)
        let url2 = try store.quickAdd("剪刀", calendar: cal)
        #expect(url.lastPathComponent == "剪刀.md" && url2.lastPathComponent == "剪刀 2.md")
        let things = store.load(calendar: cal)
        #expect(things.count == 2 && things.contains { $0.location == "厨房第二个抽屉" })
        let anker = Thing.parse(text: "---\ntype: thing\nname: 充电宝 Anker 25000mAh\n---\n", fileURL: dir.appendingPathComponent("a.md"), root: dir, calendar: cal)!
        let mac = Thing.parse(text: "---\ntype: thing\nname: MacBook Pro 14\n---\n", fileURL: dir.appendingPathComponent("m.md"), root: dir, calendar: cal)!
        #expect(ThingMatch.similar(to: "充电宝", in: [anker, mac]).map(\.name) == ["充电宝 Anker 25000mAh"])
        #expect(Set(ThingMatch.similar(to: "macbook 充电器", in: [anker, mac]).map(\.name)) == ["MacBook Pro 14", "充电宝 Anker 25000mAh"])
        #expect(ThingMatch.similar(to: "机械键盘", in: [anker, mac]).isEmpty)
    }
}


@Suite struct VisionTests {
    private func span(_ s: String) -> (String, String)? {
        FuzzyTime.parse(s, calendar: cal).map {
            (DateText.format($0.start, withTime: false, calendar: cal), DateText.format($0.end, withTime: false, calendar: cal))
        }
    }

    @Test func fuzzyTimes() {
        #expect(span("2026-12-15")! == ("2026-12-15", "2026-12-16"))
        #expect(span("2026-12")! == ("2026-12-01", "2027-01-01"))
        #expect(span("2026-12 中旬")! == ("2026-12-11", "2026-12-21"))
        #expect(span("2027-01下旬")! == ("2027-01-21", "2027-02-01"))
        #expect(span("2027年3月")! == ("2027-03-01", "2027-04-01"))
        #expect(span("2027 夏")! == ("2027-06-01", "2027-09-01"))
        #expect(span("2028秋")! == ("2028-09-01", "2028-12-01"))
        #expect(span("2027 冬")! == ("2027-12-01", "2028-03-01"))
        #expect(span("2028")! == ("2028-01-01", "2029-01-01"))
        #expect(span("寒假前") == nil && span("") == nil)
        #expect(FuzzyTime.exactDay("2026-11-21", calendar: cal) != nil && FuzzyTime.exactDay("2026-11", calendar: cal) == nil)
    }

    @Test func parsesTimelineAndListVisions() {
        let root = URL(fileURLWithPath: "/tmp/远景")
        let phd = Vision.parse(text: """
        ---
        type: vision
        title: 读 PhD
        shape: timeline
        start: 2026-10
        target: 2028 秋
        tags: 学业、研究
        ---
        > 做 agent 研究的 PhD

        ## 时间甬道
        | 时间 | checkpoint | 结果 | 一句话 |
        |---|---|---|---|
        | 2026-10 下旬 | 第一次见老师 | 到了 | 题目定了 |
        | 2027-01 下旬 | workshop 投稿 | | |
        | 寒假前 | 读完 10 篇 | | |
        """, fileURL: root.appendingPathComponent("愿景/读 PhD.md"), root: root, calendar: cal)!
        #expect(phd.summary == "做 agent 研究的 PhD" && phd.shape == .timeline && phd.tags == ["学业", "研究"])
        #expect(phd.checkpoints.map(\.result) == [.reached, .none, .none] && phd.checkpoints[2].interval == nil)
        let s = phd.span(calendar: cal)!
        #expect(DateText.format(s.start, withTime: false, calendar: cal) == "2026-10-01" && DateText.format(s.end, withTime: false, calendar: cal) == "2028-12-01")
        #expect(phd.nextCheckpoint(now: d("2026-10-22"))?.text == "workshop 投稿")

        let travel = Vision.parse(text: """
        ---
        type: vision
        title: 旅行与摄影
        shape: list
        ---
        ## 清单
        | 地方 | 状态 | 标签 | 时间 | 照片 | 备注 |
        |---|---|---|---|---|---|
        | Westside Park | 去过 | 美国、Atlanta · 公园 | 2026-10-24 | 照片/a.jpg、照片/b.jpg | |
        | Stone Mountain | 想去 | 美国, Atlanta | | | 和同学 |
        """, fileURL: root.appendingPathComponent("愿景/旅行.md"), root: root, calendar: cal)!
        #expect(travel.shape == .list && travel.places.map(\.visited) == [true, false])
        #expect(travel.places[0].tags == ["美国", "Atlanta", "公园"] && travel.places[0].photos.map(\.lastPathComponent) == ["a.jpg", "b.jpg"])
        #expect(travel.places[1].note == "和同学")
    }

    @Test func projectStepsProgressToggleAndCalendar() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = VisionStore(vault: dir)
        try FileManager.default.createDirectory(at: store.projectsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store.ideasDir, withIntermediateDirectories: true)
        let url = store.projectsDir.appendingPathComponent("EarlyEval.md")
        try """
        ---
        type: project
        title: EarlyEval workshop 论文
        vision: "[[读 PhD]]"
        status: 进行中
        target: 2027-01 下旬
        ---
        > 投出一篇 workshop 论文

        ## 步骤
        - [x] 读 EarlyEval 和 PPI
        - [ ] 写一页 pitch · 2026-10-25
        - [ ] 见老师 · 2026-10-28 15:00
        - [ ] 跑第一个实验

        ## 进展记录
        - 2026-10-22 定了路线 B
        """.write(to: url, atomically: true, encoding: .utf8)
        try "---\ntype: idea\ntitle: 拍一部纪录片\ncategory: 创作\ncreated: 2026-10-22\n---\n关于 GT 国际生的一天。\n".write(
            to: store.ideasDir.appendingPathComponent("纪录片.md"), atomically: true, encoding: .utf8)

        var snap = store.load(calendar: cal)
        var p = snap.projects[0]
        #expect(p.vision == "读 PhD" && p.goal == "投出一篇 workshop 论文" && p.steps.count == 4)
        #expect(p.doneCount == 1 && p.progress == 0.25 && p.nextStep?.text == "写一页 pitch")
        #expect(p.steps[2].hasTime && p.steps[1].date != nil && p.steps[3].date == nil)
        #expect(p.log.first?.date == "2026-10-22" && p.log.first?.text == "定了路线 B")
        #expect(snap.unfiledProjects.count == 1)
        #expect(snap.ideas.first?.category == "创作" && snap.ideas.first?.excerpt == "关于 GT 国际生的一天。")

        let week = DateInterval(start: d("2026-10-24"), end: d("2026-10-31"))
        let occ = VisionCalendar.occurrences(snap, in: week, calendar: cal)
        #expect(occ.map(\.title) == ["写一页 pitch", "见老师"] && occ[0].allDay && !occ[1].allDay)

        let before = try store.toggleStep(p.steps[1], in: p)
        #expect(before.contains("- [ ] 写一页 pitch · 2026-10-25"))
        snap = store.load(calendar: cal)
        p = snap.projects[0]
        #expect(p.doneCount == 2 && p.steps[1].done && p.steps[1].text == "写一页 pitch")
        // 文件被改过（这一行内容变了）就拒绝，不乱写
        var stale = p.steps[3]
        stale.text = "别的事"
        #expect(throws: (any Error).self) { try store.toggleStep(stale, in: p) }
    }

    @Test func pluginFlagDefaultsOff() throws {
        let c = try JSONDecoder().decode(LifeConfig.Plugins.self, from: Data(#"{"travel": true}"#.utf8))
        #expect(c.travel && !c.vision)
    }
}

@Suite struct UndatedTripTests {
    @Test func undatedTripParsesAndStaysOffCalendar() {
        let root = URL(fileURLWithPath: "/tmp/出行")
        let trip = Trip.parse(text: """
        ---
        type: trip
        title: Stone Mountain
        status: 想法
        ---
        ## 每天
        ### 第 1 天 · 待定
        | 时间 | 安排 | 地点 | 备注 |
        |---|---|---|---|
        | 10:00 | 爬山 | Stone Mountain | |
        """, fileURL: root.appendingPathComponent("Stone Mountain.md"), root: root, calendar: cal)!
        #expect(!trip.dated && trip.days.count == 1 && trip.days[0].date == nil && trip.days[0].items[0].start == nil)
        #expect(TripShare.dateRange(trip, calendar: cal) == "日期未定")
        let year = DateInterval(start: d("2026-01-01"), end: d("2027-01-01"))
        #expect(TravelCalendar.occurrences([trip], in: year, calendar: cal).isEmpty)
        #expect(!TripShare.ics(trip, options: .init(), calendar: cal).contains("DTSTART;VALUE=DATE"))
    }

    @Test func placeLinksToTrip() {
        let root = URL(fileURLWithPath: "/tmp/远景")
        let v = Vision.parse(text: """
        ---
        type: vision
        title: 旅行
        shape: list
        ---
        ## 清单
        | 地方 | 状态 | 标签 | 时间 | 照片 | 行程 | 备注 |
        |---|---|---|---|---|---|---|
        | Stone Mountain | 想去 | 美国 | | | [[Stone Mountain]] | |
        | Emory | 想去 | 美国 | | | | |
        """, fileURL: root.appendingPathComponent("愿景/旅行.md"), root: root, calendar: cal)!
        #expect(v.places.map(\.trip) == ["Stone Mountain", ""])
    }
}

@Suite struct FitnessTests {
    private let url = URL(fileURLWithPath: "/tmp/健康/动作/卧推.md")

    @Test func exerciseRecordsBestsAndHint() {
        let ex = Exercise.parse(text: """
        ---
        type: exercise
        name: 卧推
        name_en: Barbell Bench Press
        primary: chest
        secondary: front-deltoids, triceps
        day: 周三 推
        target: 3×8
        step: 5
        ---
        ## 记录
        | 日期 | 重量 | 次数 | 组数 | 备注 |
        |---|---|---|---|---|
        | 2026-10-28 | 65 | 8 | 3 | |
        | 2026-11-04 | 70 | 7 | 3 | 最后一组 7 个 |
        | 2026-11-06 | 70 | 6 | 3 | |
        """, fileURL: url, calendar: cal)!
        #expect(ex.primary == ["chest"] && ex.secondary == ["front-deltoids", "triceps"] && ex.records.count == 3)
        #expect(ex.targetSetsReps!.sets == 3 && ex.targetSetsReps!.reps == 8)
        let bests = ex.weeklyBests(calendar: cal)
        #expect(bests.count == 2 && bests[1].record.reps == 7)
        #expect(ex.nextHint?.contains("保持 70 lb") == true)
        // 做满了就加量
        var full = ex
        full.records = [ex.records[0]]
        #expect(full.nextHint?.contains("下次试 70 lb") == true)
        #expect(ex.records[0].estimated1RM.map { abs($0 - 65 * (1 + 8.0 / 30)) < 0.001 } == true)
    }

    @Test func timedTargetAndCoverage() {
        let plank = Exercise.parse(text: "---\ntype: exercise\nname: 平板支撑\nkind: timed\nprimary: abs\nsecondary: obliques\ntarget: 3×30 秒\n---\n",
                                   fileURL: url, calendar: cal)!
        #expect(plank.kind == .timed && plank.targetSetsReps!.reps == 30)
        let cov = MuscleCoverage.compute([plank])
        #expect(cov["abs"]!.primary.count == 1 && cov["obliques"]!.secondary.count == 1 && !cov["chest"]!.trained)
    }

    @Test func weekPlanParses() {
        let plan = WeekPlan.parse("""
        ## 学期一周
        | 星期 | 时间 | 内容 | 动作 |
        |---|---|---|---|
        | 周一 | 12:00–13:00 | 力量 · 背 | 高位下拉、坐姿划船 |
        | 周日 | — | 休息 | |

        - 每天拉伸
        """)
        #expect(plan.days.count == 2 && plan.days[0].exercises == ["高位下拉", "坐姿划船"] && plan.days[1].exercises.isEmpty)
        #expect(plan.notes == "- 每天拉伸" && WeekPlan.index(of: "周日") == 7)
    }

    @Test func bodyMapCoversCatalog() {
        let keys = Set((BodyMapData.anterior + BodyMapData.posterior).map(\.muscle))
        #expect(Muscle.all.allSatisfy { keys.contains($0.key) })
    }
}

@Suite struct SleepTests {
    @Test func parsesTableAndComputesAcrossMidnight() {
        let text = """
        ---
        type: health-sleep
        month: 2026-10
        ---
        # 2026-10 睡眠

        | 日期 | 入睡 | 起床 | 时长 |
        |---|---|---|---|
        | 2026-10-26 | 01:30 | 12:00 | |
        | 2026-10-27 | 23:40 | 07:10 | |
        | 2026-10-28 | | 08:00 | |
        | 2026-10-29 | 00:10 | 08:00 | 7:30 |
        """
        let nights = HealthStore.parseSleep(text, calendar: cal)
        #expect(nights.count == 4)
        #expect(nights[0].minutes == 630)
        #expect(nights[1].minutes == 450)
        #expect(nights[2].bedtime == nil && nights[2].wake == "08:00" && nights[2].minutes == nil)
        // 写了时长就用写的，不重算
        #expect(nights[3].minutes == 450)
        #expect(cal.isDate(nights[1].date, inSameDayAs: d("2026-10-27")))
    }

    @Test func averagesOnlyNightsWithDuration() {
        var s = HealthSnapshot.empty
        s.sleep = [
            SleepNight(date: d("2026-10-20"), bedtime: nil, wake: nil, minutes: 600),
            SleepNight(date: d("2026-10-26"), bedtime: "01:30", wake: "12:00", minutes: 420),
            SleepNight(date: d("2026-10-27"), bedtime: nil, wake: "08:00", minutes: nil),
            SleepNight(date: d("2026-10-28"), bedtime: "23:00", wake: "07:00", minutes: 480),
        ]
        #expect(s.averageSleep(days: 7, until: d("2026-10-28"), calendar: cal) == 450)
        #expect(s.sleep(on: d("2026-10-27"), calendar: cal)?.wake == "08:00")
        #expect(HealthFormat.sleepText(450) == "7 小时 30 分")
        #expect(HealthStore.durationMinutes("7.5h") == 450)
        #expect(HealthStore.durationMinutes("450 min") == 450)
    }

    @Test func recordsNightsInDateOrderAndReplacesSameDay() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vault) }
        let store = HealthStore(vault: vault)

        // 新建文件
        #expect(try store.recordSleep(wakeDay: d("2026-10-29"), bedtime: "0:10", wake: "0750", calendar: cal) == nil)
        // 插到前面、只给起床、同一天再记一次就替换
        try store.recordSleep(wakeDay: d("2026-10-27"), bedtime: nil, wake: "8:00", calendar: cal)
        try store.recordSleep(wakeDay: d("2026-10-28"), bedtime: "23：40", wake: "07:10", calendar: cal)
        let before = try store.recordSleep(wakeDay: d("2026-10-28"), bedtime: "23:30", wake: "07:10", calendar: cal)
        #expect(before?.contains("23:40") == true)

        let text = try String(contentsOf: store.sleepURL(d("2026-10-28"), calendar: cal), encoding: .utf8)
        #expect(text.hasPrefix("---\ntype: health-sleep\nmonth: 2026-10\n---"))
        let nights = HealthStore.parseSleep(text, calendar: cal)
        #expect(nights.map { DateText.format($0.date, withTime: false, calendar: cal) } == ["2026-10-27", "2026-10-28", "2026-10-29"])
        #expect(nights[0].bedtime == nil && nights[0].minutes == nil)
        #expect(nights[1].bedtime == "23:30" && nights[1].minutes == 460)
        #expect(nights[2].wake == "07:50" && nights[2].minutes == 460)
        #expect(text.contains("| 2026-10-29 | 00:10 | 07:50 | 7:40 |"))

        #expect(throws: HealthStore.SleepEntryError.empty) {
            try store.recordSleep(wakeDay: d("2026-10-30"), bedtime: " ", wake: nil, calendar: cal)
        }
        #expect(throws: HealthStore.SleepEntryError.badTime("晚上")) {
            try store.recordSleep(wakeDay: d("2026-10-30"), bedtime: "晚上", wake: "08:00", calendar: cal)
        }
    }
}
