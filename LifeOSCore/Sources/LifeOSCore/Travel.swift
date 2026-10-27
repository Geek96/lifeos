import Foundation

// 出行插件：`出行/` 下每次出行一个文件（frontmatter + 固定小节），`出行/想去.md` 是想去的地方。
// agent 写；App 只读，唯一会写的是“要带”清单的勾选。

/// 每天时间线里的一行
public struct TripItem: Equatable, Sendable, Identifiable {
    public var id: Int
    public var time: String
    public var text: String
    public var place: String
    public var note: String
    /// 解析出来的开始 / 结束时刻（有具体时间才有）
    public var start: Date?
    public var end: Date?
}

/// 行程里的一天
public struct TripDay: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    public var date: Date?
    public var city: String
    public var items: [TripItem]
}

/// 住宿
public struct Lodging: Equatable, Sendable, Identifiable {
    public var id: Int
    public var checkIn: Date?
    public var checkOut: Date?
    public var city: String
    public var name: String
    public var address: String
    public var confirmation: String
    public var price: String
    public var freeCancelUntil: Date?
}

/// “要带”清单的一项：记住它在文件里的第几行，勾选时只改这一行
public struct PackItem: Equatable, Sendable, Identifiable {
    public var id: Int { line }
    public var line: Int
    public var text: String
    public var done: Bool
}

public struct Trip: Equatable, Sendable, Identifiable {
    public var id: String { fileURL.path }
    public var fileURL: URL
    public var title: String
    public var destination: String
    public var route: String
    /// 没定日期的（只是个想法）为 .distantFuture，`dated` 为 false
    public var start: Date
    public var end: Date
    /// 有没有定日期
    public var dated: Bool
    public var with: String
    public var transport: String
    /// 想法 / 规划中 / 已订好 / 进行中 / 去过了
    public var status: String
    public var cover: URL?
    /// 封面是网图时的出处（作者 · 许可 · 链接）
    public var coverCredit: String
    /// 已发布的分享链接（agent 发布后写进 frontmatter 的 share_url）
    public var shareURL: URL?
    /// 和同行的人一起改的 Google Doc（agent 负责同步）
    public var gdocURL: URL?
    /// 上次和 Google Doc 同步的时间
    public var gdocSynced: Date?
    public var body: String

    public var days: [TripDay]
    public var transportTable: MarkdownTable.Table?
    public var lodging: [Lodging]
    public var deadlines: [(date: Date, text: String)]
    public var budget: [(item: String, estimate: Double?, actual: Double?)]
    public var packing: [PackItem]

    public static func == (a: Trip, b: Trip) -> Bool {
        a.fileURL == b.fileURL && a.body == b.body && a.title == b.title && a.start == b.start && a.end == b.end && a.dated == b.dated
            && a.status == b.status && a.with == b.with && a.transport == b.transport && a.cover == b.cover && a.coverCredit == b.coverCredit && a.shareURL == b.shareURL && a.gdocURL == b.gdocURL && a.gdocSynced == b.gdocSynced
    }

    public func dayCount(calendar: Calendar) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) + 1
    }

    public func isPast(now: Date, calendar: Calendar) -> Bool {
        Recurrence.endOfDay(end, calendar) < now
    }

    /// 正文里某个 `## ` 小节的原文（不含标题）
    public func section(_ name: String) -> String {
        Trip.section(name, in: body)
    }

    static func section(_ name: String, in body: String) -> String {
        var inSection = false
        var lines: [String] = []
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = line.dropFirst(3).trimmingCharacters(in: .whitespaces).hasPrefix(name)
                continue
            }
            if inSection { lines.append(line) }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - 解析

    static func parse(text: String, fileURL: URL, root: URL, calendar: Calendar) -> Trip? {
        let doc = Frontmatter.parse(text)
        let f = doc.fields
        guard f["type"] == "trip" else { return nil }
        // 没写日期的行程是“想法”：照样能打开详情页，只是不上日历、排在最后
        let parsedStart = f["start"].flatMap { DateText.parse($0, calendar: calendar) }
        let start = parsedStart ?? .distantFuture
        let end = parsedStart == nil ? start : (f["end"].flatMap { DateText.parse($0, calendar: calendar) } ?? start)
        let cover = f["cover"].flatMap { p -> URL? in
            p.isEmpty ? nil : (p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p))
        }
        let body = doc.body
        // 正文在整个文件里从第几行开始（勾选清单要用绝对行号）
        let bodyOffset = text.components(separatedBy: "\n").count - body.components(separatedBy: "\n").count
        return Trip(fileURL: fileURL, title: f["title"] ?? fileURL.deletingPathExtension().lastPathComponent,
                    destination: f["destination"] ?? "", route: f["route"] ?? "", start: start, end: end, dated: parsedStart != nil,
                    with: f["with"] ?? "", transport: f["transport"] ?? "", status: f["status"] ?? "规划中",
                    cover: cover, coverCredit: f["cover_credit"] ?? "", shareURL: f["share_url"].flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    gdocURL: f["gdoc_url"].flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    gdocSynced: f["gdoc_synced"].flatMap { DateText.parse($0, calendar: calendar) }, body: body,
                    days: parseDays(body, start: parsedStart, calendar: calendar),
                    transportTable: MarkdownTable.tables(in: section("交通", in: body)).first,
                    lodging: parseLodging(section("住宿", in: body), calendar: calendar),
                    deadlines: parseDeadlines(section("期限", in: body), calendar: calendar),
                    budget: parseBudget(section("预算", in: body)),
                    packing: parsePacking(body, offset: bodyOffset))
    }

    /// `## 每天` 下面的 `### 第 N 天 · YYYY-MM-DD · 城市`，每个下面一张 | 时间 | 安排 | 地点 | 备注 | 表
    static func parseDays(_ body: String, start: Date?, calendar: Calendar) -> [TripDay] {
        let text = section("每天", in: body)
        var days: [TripDay] = []
        var heading: String?
        var lines: [String] = []
        func flush() {
            guard let h = heading else { return }
            let parts = h.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            let date = parts.lazy.compactMap { DateText.parse($0, calendar: calendar) }.first
                ?? start.flatMap { calendar.date(byAdding: .day, value: days.count, to: calendar.startOfDay(for: $0)) }
            let city = parts.count >= 3 ? parts[2] : (parts.count == 2 && DateText.parse(parts[1], calendar: calendar) == nil ? parts[1] : "")
            let table = MarkdownTable.tables(in: lines.joined(separator: "\n")).first
            let items = (table?.rows ?? []).enumerated().compactMap { i, row -> TripItem? in
                let c = row + Array(repeating: "", count: max(0, 4 - row.count))
                guard !c[1].isEmpty || !c[0].isEmpty else { return nil }
                let (s, e) = times(c[0], on: date, calendar: calendar)
                return TripItem(id: i, time: c[0], text: c[1], place: c[2], note: c[3], start: s, end: e)
            }
            days.append(TripDay(index: days.count + 1, date: date, city: city, items: items))
        }
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("### ") {
                flush()
                heading = String(line.dropFirst(4))
                lines = []
            } else {
                lines.append(line)
            }
        }
        flush()
        return days
    }

    /// “10:00”“10:00–12:30”“10:00-12:30” → 当天的时刻
    static func times(_ s: String, on day: Date?, calendar: Calendar) -> (Date?, Date?) {
        guard let day else { return (nil, nil) }
        let parts = s.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "~", with: "-")
            .split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        func at(_ t: String) -> Date? {
            let hm = t.split(separator: ":").compactMap { Int($0) }
            guard hm.count == 2, (0..<24).contains(hm[0]), (0..<60).contains(hm[1]) else { return nil }
            return calendar.date(bySettingHour: hm[0], minute: hm[1], second: 0, of: day)
        }
        let s0 = parts.first.flatMap(at)
        let e0 = parts.count > 1 ? at(parts[1]) : nil
        return (s0, e0)
    }

    /// | 入住 | 退房 | 城市 | 名称 | 地址 | 确认号 | 价格 | 免费取消截止 |
    static func parseLodging(_ text: String, calendar: Calendar) -> [Lodging] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        return t.rows.enumerated().compactMap { i, row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let name = cell(idx("名称"))
            guard !name.isEmpty else { return nil }
            return Lodging(id: i, checkIn: DateText.parse(cell(idx("入住")), calendar: calendar),
                           checkOut: DateText.parse(cell(idx("退房")), calendar: calendar), city: cell(idx("城市")),
                           name: name, address: cell(idx("地址")), confirmation: cell(idx("确认")), price: cell(idx("价格")),
                           freeCancelUntil: DateText.parse(cell(idx("取消")), calendar: calendar))
        }
    }

    /// | 截止 | 要做的事 |
    static func parseDeadlines(_ text: String, calendar: Calendar) -> [(date: Date, text: String)] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        return t.rows.compactMap { row in
            guard row.count >= 2, let d = DateText.parse(row[0], calendar: calendar), !row[1].isEmpty else { return nil }
            return (d, row[1])
        }.sorted { $0.date < $1.date }
    }

    /// | 项目 | 预计 | 实际 |
    static func parseBudget(_ text: String) -> [(item: String, estimate: Double?, actual: Double?)] {
        guard let t = MarkdownTable.tables(in: text).first else { return [] }
        return t.rows.compactMap { row in
            guard let item = row.first, !item.isEmpty else { return nil }
            return (item, row.count > 1 ? HealthStore.number(row[1]) : nil, row.count > 2 ? HealthStore.number(row[2]) : nil)
        }
    }

    /// `## 要带` 下的 `- [ ] xxx` / `- [x] xxx`
    static func parsePacking(_ body: String, offset: Int) -> [PackItem] {
        var inSection = false
        var out: [PackItem] = []
        for (i, line) in body.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = line.dropFirst(3).trimmingCharacters(in: .whitespaces).hasPrefix("要带")
                continue
            }
            guard inSection, let item = checkbox(line) else { continue }
            out.append(PackItem(line: offset + i, text: item.text, done: item.done))
        }
        return out
    }

    static func checkbox(_ line: String) -> (text: String, done: Bool)? {
        let t = line.trimmingCharacters(in: .whitespaces)
        for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where t.hasPrefix(prefix) {
            return (String(t.dropFirst(prefix.count)), done)
        }
        return nil
    }
}

/// 想去的地方
public struct Destination: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var location: String
    public var why: String
    public var season: String
    public var howToGo: String
    public var duration: String
    public var budget: String
}

/// `出行/` 目录
public struct TravelStore: Sendable {
    public let root: URL

    public init(vault: URL) { root = vault.appendingPathComponent("出行") }

    public var wishlistURL: URL { root.appendingPathComponent("想去.md") }
    /// 分享用的网页放这里，agent 把它发布成链接
    public var shareDir: URL { root.appendingPathComponent("分享") }
    /// 和 Google Doc 同步的基准（上次同步时两边的样子），agent 维护
    public var syncDir: URL { root.appendingPathComponent("同步") }
    public var photosDir: URL { root.appendingPathComponent("照片") }

    public func loadTrips(calendar: Calendar = .current) -> [Trip] {
        HealthStore.markdownFiles(in: root)
            .filter { $0 != wishlistURL && !$0.path.hasPrefix(photosDir.path + "/") && !$0.path.hasPrefix(shareDir.path + "/") && !$0.path.hasPrefix(syncDir.path + "/") }
            .compactMap { url in
                (try? String(contentsOf: url, encoding: .utf8)).flatMap { Trip.parse(text: $0, fileURL: url, root: root, calendar: calendar) }
            }
            .sorted { $0.start < $1.start }
    }

    public func loadWishlist() -> [Destination] {
        guard let text = try? String(contentsOf: wishlistURL, encoding: .utf8),
              let t = MarkdownTable.tables(in: Frontmatter.parse(text).body).first else { return [] }
        func idx(_ n: String) -> Int? { t.header.firstIndex { $0.contains(n) } }
        return t.rows.compactMap { row in
            func cell(_ j: Int?) -> String { j.flatMap { $0 < row.count ? row[$0] : nil } ?? "" }
            let name = cell(idx("地方") ?? 0)
            guard !name.isEmpty else { return nil }
            return Destination(name: name, location: cell(idx("在哪")), why: cell(idx("为什么")), season: cell(idx("季节")),
                               howToGo: cell(idx("怎么去")), duration: cell(idx("几天")), budget: cell(idx("预算")))
        }
    }

    /// 勾选 / 取消“要带”的一项：只改那一行，并核对内容没变。返回改动前的全文（撤销用）。
    @discardableResult
    public func togglePacking(_ item: PackItem, in trip: Trip) throws -> String {
        let before = try String(contentsOf: trip.fileURL, encoding: .utf8)
        var lines = before.components(separatedBy: "\n")
        guard item.line < lines.count, let current = Trip.checkbox(lines[item.line]), current.text == item.text else {
            throw CocoaError(.fileWriteUnknown)
        }
        let indent = String(lines[item.line].prefix { $0 == " " || $0 == "\t" })
        lines[item.line] = indent + (current.done ? "- [ ] " : "- [x] ") + current.text
        try lines.joined(separator: "\n").write(to: trip.fileURL, atomically: true, encoding: .utf8)
        return before
    }
}

/// 出行在日历上的出现
public enum TravelCalendar {
    public static func occurrences(_ trips: [Trip], in range: DateInterval, calendar: Calendar) -> [Occurrence] {
        var out: [Occurrence] = []
        for trip in trips where trip.dated {
            let key = "trip:\(trip.id)"
            let s = calendar.startOfDay(for: trip.start)
            let e = Recurrence.endOfDay(trip.end, calendar)
            if DateInterval(start: s, end: max(e, s)).intersects(range) {
                out.append(Occurrence(id: key, style: .event, title: "出行：\(trip.title)",
                                      subtitle: trip.route.isEmpty ? trip.destination : trip.route,
                                      start: s, end: e, allDay: true, sourceURL: trip.fileURL, location: trip.destination))
            }
            for day in trip.days {
                for item in day.items {
                    guard let st = item.start, range.contains(st) else { continue }
                    out.append(Occurrence(id: "\(key)#d\(day.index)-\(item.id)", style: .event, title: item.text,
                                          subtitle: trip.title, start: st, end: item.end, sourceURL: trip.fileURL,
                                          location: item.place))
                }
            }
            for (i, d) in trip.deadlines.enumerated() where range.contains(calendar.startOfDay(for: d.date)) {
                out.append(Occurrence(id: "\(key)#ddl\(i)", style: .deadline, title: d.text, subtitle: trip.title,
                                      start: calendar.startOfDay(for: d.date), allDay: true, sourceURL: trip.fileURL))
            }
            for l in trip.lodging {
                guard let c = l.freeCancelUntil, range.contains(calendar.startOfDay(for: c)) else { continue }
                out.append(Occurrence(id: "\(key)#cancel\(l.id)", style: .deadline, title: "免费取消截止：\(l.name)",
                                      subtitle: trip.title, start: calendar.startOfDay(for: c), allDay: true, sourceURL: trip.fileURL))
            }
        }
        return out
    }
}
