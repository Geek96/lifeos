import Foundation

// 收藏插件：做到的事攒积分，积分抽卡，抽到的卡收进陈列馆。
// vault 里：
//   收藏/卡池/<池名>/卡池.json + 图/   一个卡池一个文件夹（卡池是插件，可以加别的池）
//   收藏/积分.md                       积分账本：只加不减，一件事一行，“编号”保证同一件事只记一次
//   收藏/抽卡记录.md                   每抽一张一行（花了多少、重复退了多少）
// 只有电脑版写这两个文件（算积分、抽卡）；手机版只读。

// MARK: - 卡池

public enum CardRarity: String, Codable, CaseIterable, Sendable, Comparable {
    case common, rare, epic, legend

    public var label: String {
        switch self { case .common: "普通"; case .rare: "稀有"; case .epic: "史诗"; case .legend: "传说" }
    }
    /// 边框
    public var frame: String {
        switch self { case .common: "铜"; case .rare: "银"; case .epic: "金"; case .legend: "镭射" }
    }
    /// 抽卡概率（百分比）
    public var weight: Double {
        switch self { case .common: 70; case .rare: 22; case .epic: 7; case .legend: 1 }
    }
    /// 抽到重复的退多少积分
    public var refund: Int {
        switch self { case .common: 5; case .rare: 10; case .epic: 20; case .legend: 50 }
    }

    private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (a: CardRarity, b: CardRarity) -> Bool { a.order < b.order }
}

public struct CollectibleCard: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var nameEn: String
    /// 小套装（新七大奇迹、印象派……）
    public var set: String
    public var rarity: CardRarity
    /// 背面的三行资料：[标签, 内容]
    public var facts: [[String]]
    public var story: String
    public var fun: String
    /// 相对卡池文件夹的图片路径
    public var image: String
    /// 名画：图片出处和授权
    public var source: String?
    public var license: String?
}

public struct CardPool: Equatable, Sendable, Identifiable {
    /// 画法：poster = 按卡的比例画好、铺满；painting = 真画，整幅装在衬纸里不裁
    public enum Style: String, Codable, Sendable { case poster, painting }

    public var id: String
    public var name: String
    public var nameEn: String
    public var style: Style
    /// 陈列馆里排第几（小的在前）
    public var order: Int
    /// 陈列馆里的总声明：图从哪里来
    public var credit: String
    public var cards: [CollectibleCard]
    public var folder: URL

    private struct File: Codable {
        var id: String
        var name: String
        var nameEn: String?
        var style: Style?
        var order: Int?
        var credit: String?
        var cards: [CollectibleCard]
    }

    public static func load(folder: URL) -> CardPool? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(CardsStore.poolFileName)),
              let f = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return CardPool(id: f.id, name: f.name, nameEn: f.nameEn ?? "", style: f.style ?? .poster, order: f.order ?? 99, credit: f.credit ?? "",
                        cards: f.cards, folder: folder)
    }

    /// 小套装，按卡池里第一次出现的顺序
    public var sets: [String] {
        var seen = Set<String>()
        return cards.map(\.set).filter { seen.insert($0).inserted }
    }

    public func cards(in set: String) -> [CollectibleCard] { cards.filter { $0.set == set } }

    public func card(_ id: String) -> CollectibleCard? { cards.first { $0.id == id } }

    public func imageURL(_ card: CollectibleCard) -> URL { folder.appendingPathComponent(card.image) }

    /// “012/030”
    public func number(_ card: CollectibleCard) -> String {
        let i = (cards.firstIndex { $0.id == card.id } ?? 0) + 1
        return String(format: "%03d/%03d", i, cards.count)
    }
}

// MARK: - 积分与抽卡记录

/// 积分账本的一行
public struct PointsEntry: Equatable, Sendable, Identifiable {
    public var id: String { key }
    public var date: Date
    public var text: String
    public var points: Int
    /// 同一件事只记一次：`diet-protein:2026-11-05`、`train:2026-11-05 力量.md`……
    public var key: String

    public init(date: Date, text: String, points: Int, key: String) {
        self.date = date
        self.text = text
        self.points = points
        self.key = key
    }
}

/// 抽到的一张
public struct CardDraw: Equatable, Sendable {
    public var time: Date
    public var pool: String
    public var card: String
    public var rarity: CardRarity
    public var isNew: Bool
    /// 这张花了多少（十连每张 18）；免费的是 0
    public var cost: Int
    /// 重复退回的积分
    public var refund: Int
    /// 周日送的免费一抽
    public var free: Bool

    public init(time: Date, pool: String, card: String, rarity: CardRarity, isNew: Bool, cost: Int, refund: Int, free: Bool) {
        self.time = time
        self.pool = pool
        self.card = card
        self.rarity = rarity
        self.isNew = isNew
        self.cost = cost
        self.refund = refund
        self.free = free
    }

    /// “pool/card”
    public var cardKey: String { "\(pool)/\(card)" }
}

public struct CardsSnapshot: Equatable, Sendable {
    public var pools: [CardPool]
    public var ledger: [PointsEntry]
    public var draws: [CardDraw]
    /// 从哪天开始算积分（积分.md 的 `since`）
    public var since: Date?

    public static let empty = CardsSnapshot(pools: [], ledger: [], draws: [], since: nil)

    public var earned: Int { ledger.reduce(0) { $0 + $1.points } }
    public var balance: Int { earned - draws.reduce(0) { $0 + $1.cost } + draws.reduce(0) { $0 + $1.refund } }

    /// 每张卡抽到了几次（“pool/card” → 次数）
    public var owned: [String: Int] {
        draws.reduce(into: [:]) { $0[$1.cardKey, default: 0] += 1 }
    }

    public func count(_ pool: CardPool, _ card: CollectibleCard) -> Int { owned["\(pool.id)/\(card.id)"] ?? 0 }

    public func ownedCount(_ pool: CardPool, set: String? = nil) -> Int {
        let o = owned
        return pool.cards.filter { (set == nil || $0.set == set) && o["\(pool.id)/\($0.id)"] != nil }.count
    }

    public func pool(_ id: String) -> CardPool? { pools.first { $0.id == id } }

    /// 每周日送一抽：从开始那周起，周日到了的周数 − 已经用掉的
    public func freeDraws(now: Date, calendar: Calendar) -> Int {
        guard let since else { return 0 }
        var cal = calendar
        cal.firstWeekday = 2
        guard var week = cal.dateInterval(of: .weekOfYear, for: since)?.start else { return 0 }
        var n = 0
        while let sunday = cal.date(byAdding: .day, value: 6, to: week), sunday <= now {
            n += 1
            guard let next = cal.date(byAdding: .day, value: 7, to: week) else { break }
            week = next
        }
        return max(n - draws.filter(\.free).count, 0)
    }
}

// MARK: - 读写

public struct CardsStore: Sendable {
    public static let poolFileName = "卡池.json"

    public let root: URL
    public init(vault: URL) { root = vault.appendingPathComponent("收藏") }

    public var poolsDir: URL { root.appendingPathComponent("卡池") }
    public var pointsURL: URL { root.appendingPathComponent("积分.md") }
    public var drawsURL: URL { root.appendingPathComponent("抽卡记录.md") }

    public func load(calendar: Calendar = .current) -> CardsSnapshot {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: poolsDir, includingPropertiesForKeys: nil)) ?? []
        // 卡池按 order 排；每个池子里卡的顺序就是编号
        let pools = folders.compactMap(CardPool.load).sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        let pointsText = (try? String(contentsOf: pointsURL, encoding: .utf8)) ?? ""
        let since = Frontmatter.parse(pointsText).fields["since"].flatMap { DateText.parse($0, calendar: calendar) }
        return CardsSnapshot(pools: pools, ledger: Self.parseLedger(pointsText, calendar: calendar),
                             draws: Self.parseDraws((try? String(contentsOf: drawsURL, encoding: .utf8)) ?? "", calendar: calendar),
                             since: since)
    }

    // 积分.md

    static let ledgerHeader = "| 日期 | 做到了什么 | 积分 | 编号 |\n|---|---|---|---|"

    public static func parseLedger(_ text: String, calendar: Calendar) -> [PointsEntry] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains("编号") }) else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex(of: n) }
        guard let d = idx("日期"), let x = idx("做到了什么"), let p = idx("积分"), let k = idx("编号") else { return [] }
        return t.rows.compactMap { r in
            guard r.count > max(d, x, p, k), let date = DateText.parse(r[d], calendar: calendar), let pts = Int(r[p]) else { return nil }
            return PointsEntry(date: date, text: r[x], points: pts, key: r[k].replacingOccurrences(of: "`", with: ""))
        }
    }

    static func cell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "／").replacingOccurrences(of: "\n", with: " ")
    }

    /// 记上还没记过的（按编号去重）。账本不存在就新建，`since` 写成 `start`。返回记了几行
    @discardableResult
    public func appendPoints(_ entries: [PointsEntry], start: Date, calendar: Calendar = .current,
                             scratch: URL = FileManager.default.temporaryDirectory) throws -> Int {
        var added = 0
        try SafeFileWrite.update(pointsURL, scratch: scratch) { old in
            let existing = Set(Self.parseLedger(old ?? "", calendar: calendar).map(\.key))
            let new = entries.filter { !existing.contains($0.key) }.sorted { ($0.date, $0.key) < ($1.date, $1.key) }
            added = new.count
            guard !new.isEmpty || old == nil else { return nil }
            var text = old ?? """
            ---
            type: cards-points
            since: \(DateText.format(start, withTime: false, calendar: calendar))
            ---
            # 积分

            只加不减：做到了就记一行。电脑版 LifeOS 打开时自动算、自动补，同一件事只记一次（看“编号”）。规则见 `.lifeos/RULES.md` 的“收藏”。

            \(Self.ledgerHeader)

            """
            if !text.contains("| 编号 |") { text += (text.hasSuffix("\n") ? "\n" : "\n\n") + Self.ledgerHeader + "\n" }
            if !text.hasSuffix("\n") { text += "\n" }
            for e in new {
                text += "| \(DateText.format(e.date, withTime: false, calendar: calendar)) | \(Self.cell(e.text)) | \(e.points) | `\(e.key)` |\n"
            }
            return text
        }
        return added
    }

    // 抽卡记录.md

    static let drawsHeader = "| 时间 | 卡池 | 卡 | 稀有度 | 新卡 | 花费 | 退还 | 编号 |\n|---|---|---|---|---|---|---|---|"

    public static func parseDraws(_ text: String, calendar: Calendar) -> [CardDraw] {
        guard let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first(where: { $0.header.contains("编号") }) else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex(of: n) }
        guard let tm = idx("时间"), let r = idx("稀有度"), let nw = idx("新卡"), let c = idx("花费"), let rf = idx("退还"), let k = idx("编号")
        else { return [] }
        return t.rows.compactMap { row in
            guard row.count > max(tm, r, nw, c, rf, k), let time = DateText.parse(row[tm], calendar: calendar) else { return nil }
            let key = row[k].replacingOccurrences(of: "`", with: "").split(separator: "/", maxSplits: 1).map(String.init)
            guard key.count == 2 else { return nil }
            let rarity = CardRarity.allCases.first { row[r].contains($0.label) } ?? .common
            let free = row[c].contains("免费")
            return CardDraw(time: time, pool: key[0], card: key[1], rarity: rarity, isNew: row[nw].contains("新"),
                            cost: free ? 0 : Int(row[c]) ?? 0, refund: Int(row[rf]) ?? 0, free: free)
        }
    }

    public func appendDraws(_ draws: [CardDraw], pools: [CardPool], calendar: Calendar = .current,
                            scratch: URL = FileManager.default.temporaryDirectory) throws {
        guard !draws.isEmpty else { return }
        try SafeFileWrite.update(drawsURL, scratch: scratch) { old in
            var text = old ?? """
            ---
            type: cards-draws
            ---
            # 抽卡记录

            电脑版 LifeOS 抽卡时写。一张一行；“编号”是 卡池/卡。

            \(Self.drawsHeader)

            """
            if !text.hasSuffix("\n") { text += "\n" }
            for d in draws {
                let pool = pools.first { $0.id == d.pool }
                let name = pool?.card(d.card)?.name ?? d.card
                let cost = d.free ? "免费" : "\(d.cost)"
                text += "| \(DateText.format(d.time, withTime: true, calendar: calendar)) | \(Self.cell(pool?.name ?? d.pool)) | \(Self.cell(name)) | \(d.rarity.label) | \(d.isNew ? "新" : "重复") | \(cost) | \(d.refund) | `\(d.cardKey)` |\n"
            }
            return text
        }
    }
}

// MARK: - 抽卡

public enum CardDrawer {
    public static let singleCost = 20
    public static let tenCost = 180
    /// 连着这么多张都是普通，下一张至少稀有
    public static let pity = 10

    /// 抽 `count` 张（1 或 10）。十连里至少一张史诗以上；没集齐的优先给新卡；
    /// 重复的按稀有度退积分。`history` 用来算保底（之前连着几张普通）。
    public static func draw<G: RandomNumberGenerator>(count: Int, from pool: CardPool, snapshot: CardsSnapshot, free: Bool = false,
                                                      now: Date = Date(), rng: inout G) -> [CardDraw] {
        guard !pool.cards.isEmpty else { return [] }
        var owned = snapshot.owned
        var commonsInARow = snapshot.draws.reversed().prefix { $0.rarity == .common }.count
        var result: [CardDraw] = []
        let cost = free ? 0 : (count >= 10 ? tenCost / count : singleCost)
        for i in 0..<count {
            var floor: CardRarity = .common
            if commonsInARow >= pity - 1 { floor = .rare }
            if count >= 10, i == count - 1, !result.contains(where: { $0.rarity >= .epic }) { floor = .epic }
            let rarity = available(roll(floor: floor, rng: &rng), in: pool)
            let atRarity = pool.cards.filter { $0.rarity == rarity }
            let fresh = atRarity.filter { owned["\(pool.id)/\($0.id)"] == nil }
            let card = (fresh.isEmpty ? atRarity : fresh).randomElement(using: &rng)!
            let key = "\(pool.id)/\(card.id)"
            let isNew = owned[key] == nil
            owned[key, default: 0] += 1
            commonsInARow = rarity == .common ? commonsInARow + 1 : 0
            result.append(CardDraw(time: now, pool: pool.id, card: card.id, rarity: rarity, isNew: isNew, cost: cost,
                                   refund: isNew ? 0 : rarity.refund, free: free))
        }
        return result
    }

    /// 按概率抽稀有度，不低于 `floor`
    static func roll<G: RandomNumberGenerator>(floor: CardRarity, rng: inout G) -> CardRarity {
        let options = CardRarity.allCases.filter { $0 >= floor }
        let total = options.reduce(0) { $0 + $1.weight }
        var x = Double.random(in: 0..<total, using: &rng)
        for r in options {
            if x < r.weight { return r }
            x -= r.weight
        }
        return options.last!
    }

    /// 卡池里没有这个稀有度的卡：往下找，再往上找
    static func available(_ r: CardRarity, in pool: CardPool) -> CardRarity {
        let have = Set(pool.cards.map(\.rarity))
        if have.contains(r) { return r }
        let all = CardRarity.allCases
        let i = all.firstIndex(of: r)!
        return all[..<i].reversed().first(where: have.contains) ?? all[(i + 1)...].first(where: have.contains) ?? .common
    }
}

// MARK: - 积分怎么来

/// 只加不减：从已有的记录算出“做到了的事”，每件事一个编号。账本里没有的就补上。
/// 每天：饮食记全 +2、蛋白质达标 +3、热量达到目标 +2；练一次 +5，破个人纪录 +3（一天最多一次）；
/// 专注每满 1 小时 +2（一天最多 6 小时）；记了睡眠 +1，睡够 7 小时再 +2。
/// 每周（周一到周日过完）：饮食记全 ≥ 5 天 +10、练 ≥ 3 次 +10、专注 ≥ 15 小时 +10、记睡眠 ≥ 5 晚 +5。
/// 每月（过完）：练 ≥ 12 次 +30、专注 ≥ 60 小时 +30、做了身体复测 +20。
/// 远景：想法变成项目 +1、项目做完了 +1。出行（去过了）：当天往返 +5，过夜的 +20。
public enum CardPoints {
    public static func awards(health: HealthSnapshot, focus: [FocusSession], vision: VisionSnapshot, trips: [Trip],
                              since: Date, now: Date, calendar: Calendar) -> [PointsEntry] {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.startOfDay(for: since)
        let today = cal.startOfDay(for: now)
        func day(_ d: Date) -> String { DateText.format(d, withTime: false, calendar: cal) }
        var out: [PointsEntry] = []
        func add(_ d: Date, _ text: String, _ pts: Int, _ key: String) { out.append(PointsEntry(date: d, text: text, points: pts, key: key)) }

        // 每天
        var days: [Date] = []
        var d = start
        while d <= today {
            days.append(d)
            guard let n = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = n
        }
        var dietComplete = Set<Date>()
        for d in days {
            let diet = health.day(d, calendar: cal)
            if diet.isComplete(today: now, calendar: cal) {
                dietComplete.insert(d)
                add(d, "饮食记全了", 2, "diet-complete:\(day(d))")
            }
            if let t = health.targets(on: d, calendar: cal), diet.meals.contains(where: \.isEstimated) {
                if t.protein > 0, diet.total.protein >= t.protein { add(d, "蛋白质达标", 3, "diet-protein:\(day(d))") }
                if t.kcal > 0, diet.total.kcal >= t.kcal { add(d, "热量达到目标", 2, "diet-kcal:\(day(d))") }
            }
            let hours = min(Int(FocusSummary.minutes(on: d, in: focus, calendar: cal) / 60), 6)
            if hours > 0 {
                for h in 1...hours { add(d, "专注满 \(h) 小时", 2, "focus:\(day(d)):\(h)") }
            }
        }
        let range = DateInterval(start: start, end: cal.date(byAdding: .day, value: 1, to: today) ?? now)
        for s in health.sessions where range.contains(s.date) && s.date < now {
            add(cal.startOfDay(for: s.date), "练了一次：\(s.title)", 5, "train:\(s.fileURL.lastPathComponent)")
        }
        // 个人纪录：某个动作这次的成绩超过之前所有记录（估算 1RM，没有就比重量，再没有就比次数）
        var prDays: [Date: String] = [:]
        for ex in health.exercises {
            var best: Double?
            for r in ex.records.sorted(by: { $0.date < $1.date }) {
                guard let v = r.estimated1RM ?? r.weight ?? r.reps else { continue }
                if let b = best, v > b, range.contains(r.date), prDays[cal.startOfDay(for: r.date)] == nil {
                    prDays[cal.startOfDay(for: r.date)] = ex.name
                }
                best = max(best ?? v, v)
            }
        }
        for (d, name) in prDays { add(d, "破了个人纪录：\(name)", 3, "pr:\(day(d))") }
        var sleepDays = Set<Date>()
        for n in health.sleep where range.contains(n.date) {
            let d = cal.startOfDay(for: n.date)
            sleepDays.insert(d)
            add(d, "记了睡眠", 1, "sleep:\(day(d))")
            if let m = n.minutes, m >= 420 { add(d, "睡够 7 小时", 2, "sleep7:\(day(d))") }
        }

        // 每周（过完了的）
        if var week = cal.dateInterval(of: .weekOfYear, for: start) {
            while week.end <= today {
                let last = cal.date(byAdding: .day, value: -1, to: week.end) ?? week.end
                let tag = "week:\(day(week.start))"
                let inWeek = { (x: Date) in week.contains(x) && x < week.end }
                if dietComplete.filter(inWeek).count >= 5 { add(last, "这周饮食记全 5 天以上", 10, "\(tag):diet") }
                if health.sessions.filter({ inWeek($0.date) }).count >= 3 { add(last, "这周练了 3 次以上", 10, "\(tag):train") }
                if focus.filter({ inWeek($0.start) }).reduce(0, { $0 + $1.minutes }) >= 15 * 60 { add(last, "这周专注 15 小时以上", 10, "\(tag):focus") }
                if sleepDays.filter(inWeek).count >= 5 { add(last, "这周记了 5 晚以上睡眠", 5, "\(tag):sleep") }
                guard let next = cal.dateInterval(of: .weekOfYear, for: week.end) else { break }
                week = next
            }
        }
        // 每月（过完了的）
        if var month = cal.dateInterval(of: .month, for: start) {
            while month.end <= today {
                let last = cal.date(byAdding: .day, value: -1, to: month.end) ?? month.end
                let tag = "month:\(DateText.format(month.start, withTime: false, calendar: cal).prefix(7))"
                let inMonth = { (x: Date) in x >= month.start && x < month.end }
                if health.sessions.filter({ inMonth($0.date) }).count >= 12 { add(last, "这个月练了 12 次以上", 30, "\(tag):train") }
                if focus.filter({ inMonth($0.start) }).reduce(0, { $0 + $1.minutes }) >= 60 * 60 { add(last, "这个月专注 60 小时以上", 30, "\(tag):focus") }
                if health.tests.contains(where: { inMonth($0.date) }) { add(last, "这个月做了身体复测", 20, "\(tag):test") }
                guard let next = cal.dateInterval(of: .month, for: month.end) else { break }
                month = next
            }
        }

        // 远景：没有日期，第一次看到时记在今天
        for idea in vision.ideas where idea.status.contains("变成项目") {
            add(today, "想法变成项目：\(idea.title)", 1, "idea:\(idea.title)")
        }
        for p in vision.projects where p.status.contains("做完") {
            add(today, "项目做完了：\(p.title)", 1, "project:\(p.title)")
        }
        // 出行：去过了、结束在开始算积分之后
        for t in trips where t.dated && t.status.contains("去过") && t.end >= start && t.end <= now {
            let overnight = !cal.isDate(t.start, inSameDayAs: t.end)
            add(cal.startOfDay(for: t.end), (overnight ? "出行（过夜）：" : "出行：") + t.title, overnight ? 20 : 5,
                "trip:\(t.fileURL.lastPathComponent)")
        }
        return out
    }
}
