import Foundation

/// 把一次出行变成可以分享的东西：微信文字、日历文件（.ics）、网页（发布成分享链接用）。
/// 默认不带价格、确认号和住址、要带清单，由用户每次分享时决定。
public enum TripShare {
    public struct Options: Equatable, Sendable {
        /// 价格和预算
        public var prices = false
        /// 住宿确认号、住址、交通订单
        public var privateDetails = false
        /// 要带清单
        public var packing = false
        public init(prices: Bool = false, privateDetails: Bool = false, packing: Bool = false) {
            self.prices = prices
            self.privateDetails = privateDetails
            self.packing = packing
        }
    }

    // MARK: - 微信文字

    public static func text(_ trip: Trip, options: Options = .init(), calendar: Calendar) -> String {
        var out: [String] = []
        out.append("【\(trip.title)】")
        let route = trip.route.isEmpty ? trip.destination : trip.route
        if !route.isEmpty { out.append("路线：\(route)") }
        out.append("日期：\(dateRange(trip, calendar: calendar))")
        if !trip.with.isEmpty { out.append("同行：\(trip.with)") }
        if !trip.transport.isEmpty { out.append("交通：\(trip.transport)") }

        for day in trip.days {
            out.append("")
            var head = "▍第 \(day.index) 天"
            if let d = day.date { head += " \(md(d, calendar)) \(weekday(d, calendar))" }
            if !day.city.isEmpty { head += " · \(day.city)" }
            out.append(head)
            if day.items.isEmpty { out.append("（还没排）") }
            for item in day.items {
                var line = item.time.isEmpty ? "· " : "\(item.time)  "
                line += item.text
                if !item.place.isEmpty { line += "（\(item.place)）" }
                out.append(line)
            }
            if let l = lodgingFor(day, trip, calendar) {
                out.append("住：\(l.name)" + (options.privateDetails && !l.address.isEmpty ? "，\(l.address)" : ""))
            }
        }

        if !trip.lodging.isEmpty {
            out.append("")
            out.append("▍住宿")
            for l in trip.lodging {
                var line = "\(l.name)"
                if let i = l.checkIn, let o = l.checkOut { line += "  \(md(i, calendar))–\(md(o, calendar))" }
                if options.privateDetails {
                    if !l.address.isEmpty { line += "\n  地址：\(l.address)" }
                    if !l.confirmation.isEmpty { line += "\n  确认号：\(l.confirmation)" }
                }
                if options.prices && !l.price.isEmpty { line += "\n  价格：\(l.price)" }
                out.append(line)
            }
        }

        if let t = trip.transportTable, !t.rows.isEmpty {
            out.append("")
            out.append("▍交通")
            let hidden = options.privateDetails ? Set<Int>() : Set(t.header.enumerated().filter { $0.element.contains("订单") }.map(\.offset))
            for row in t.rows {
                out.append(row.enumerated().filter { !hidden.contains($0.offset) && !$0.element.isEmpty }.map(\.element).joined(separator: "  "))
            }
        }

        let notes = plainLines(trip.section("地点"))
        if !notes.isEmpty { out.append(""); out.append("▍须知"); out += notes }
        let docs = plainLines(trip.section("证件"))
        if !docs.isEmpty { out.append(""); out.append("▍证件"); out += docs }

        if options.packing && !trip.packing.isEmpty {
            out.append("")
            out.append("▍要带")
            out += trip.packing.map { ($0.done ? "☑ " : "☐ ") + $0.text }
        }
        if options.prices && !trip.budget.isEmpty {
            out.append("")
            out.append("▍预算")
            for b in trip.budget { out.append("\(b.item)：\(b.estimate.map(money) ?? "—")") }
            out.append("合计：\(money(trip.budget.compactMap(\.estimate).reduce(0, +)))")
        }
        return out.joined(separator: "\n")
    }

    // MARK: - 日历文件

    /// iCalendar：整趟行程（全天）、带时间的安排、出发前的期限
    public static func ics(_ trip: Trip, options: Options = .init(), calendar: Calendar, now: Date = Date()) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//LifeOS//Trip//ZH", "CALSCALE:GREGORIAN", "METHOD:PUBLISH"]
        let stamp = utc(now)
        let uidBase = abs(trip.fileURL.path.hashValue)
        func event(_ uid: String, _ props: [String]) {
            lines += ["BEGIN:VEVENT", "UID:\(uid)@lifeos", "DTSTAMP:\(stamp)"] + props + ["END:VEVENT"]
        }
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.end)) ?? trip.end
        if trip.dated {
            event("\(uidBase)-trip", ["DTSTART;VALUE=DATE:\(ymd(trip.start, calendar))", "DTEND;VALUE=DATE:\(ymd(endExclusive, calendar))",
                                      "SUMMARY:\(escape(trip.title))",
                                      "DESCRIPTION:\(escape(text(trip, options: options, calendar: calendar)))"])
        }
        for day in trip.days {
            for item in day.items {
                guard let s = item.start else { continue }
                let e = item.end ?? s.addingTimeInterval(3600)
                var props = ["DTSTART:\(utc(s))", "DTEND:\(utc(max(e, s)))", "SUMMARY:\(escape(item.text))"]
                if !item.place.isEmpty { props.append("LOCATION:\(escape(item.place))") }
                if !item.note.isEmpty { props.append("DESCRIPTION:\(escape(item.note))") }
                event("\(uidBase)-d\(day.index)-\(item.id)", props)
            }
        }
        for (i, d) in trip.deadlines.enumerated() {
            let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: d.date)) ?? d.date
            event("\(uidBase)-ddl\(i)", ["DTSTART;VALUE=DATE:\(ymd(d.date, calendar))", "DTEND;VALUE=DATE:\(ymd(next, calendar))",
                                          "SUMMARY:\(escape("【\(trip.title)】\(d.text)"))"])
        }
        lines.append("END:VCALENDAR")
        // RFC 5545：行尾 CRLF，长行折叠
        return lines.flatMap(fold).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - 网页（发布成分享链接）

    public static func html(_ trip: Trip, options: Options = .init(), calendar: Calendar) -> String {
        let route = trip.route.isEmpty ? trip.destination : trip.route
        var body = """
        <header><h1>\(h(trip.title))</h1>
        <p class="sub">\(h(route))</p>
        <p class="meta">\(h(dateRange(trip, calendar: calendar)))\(trip.with.isEmpty ? "" : " · 同行：" + h(trip.with))\(trip.transport.isEmpty ? "" : " · " + h(trip.transport))</p></header>
        """
        for day in trip.days {
            var head = "第 \(day.index) 天"
            if let d = day.date { head += " · \(md(d, calendar)) \(weekday(d, calendar))" }
            if !day.city.isEmpty { head += " · \(day.city)" }
            body += "<section class=\"day\"><h2>\(h(head))</h2>"
            if day.items.isEmpty { body += "<p class=\"muted\">还没排</p>" }
            body += "<ol class=\"timeline\">"
            for item in day.items {
                body += "<li><span class=\"time\">\(h(item.time.isEmpty ? "—" : item.time))</span><div><strong>\(h(item.text))</strong>"
                if !item.place.isEmpty { body += "<div class=\"muted\">\(h(item.place))</div>" }
                if !item.note.isEmpty { body += "<div class=\"muted\">\(h(item.note))</div>" }
                body += "</div></li>"
            }
            body += "</ol>"
            if let l = lodgingFor(day, trip, calendar) {
                body += "<p class=\"stay\">今晚住：\(h(l.name))\(options.privateDetails && !l.address.isEmpty ? "（\(h(l.address))）" : "")</p>"
            }
            body += "</section>"
        }
        if !trip.lodging.isEmpty {
            body += "<section><h2>住宿</h2><ul>"
            for l in trip.lodging {
                var li = "<strong>\(h(l.name))</strong>"
                if let i = l.checkIn, let o = l.checkOut { li += " · \(md(i, calendar))–\(md(o, calendar))" }
                if options.privateDetails && !l.address.isEmpty { li += "<div class=\"muted\">\(h(l.address))</div>" }
                if options.privateDetails && !l.confirmation.isEmpty { li += "<div class=\"muted\">确认号 \(h(l.confirmation))</div>" }
                if options.prices && !l.price.isEmpty { li += "<div class=\"muted\">\(h(l.price))</div>" }
                body += "<li>\(li)</li>"
            }
            body += "</ul></section>"
        }
        for (title, key) in [("须知", "地点"), ("证件", "证件"), ("天气", "天气")] {
            let lines = plainLines(trip.section(key))
            if !lines.isEmpty { body += "<section><h2>\(title)</h2><ul>" + lines.map { "<li>\(h(String($0.dropFirst(2))))</li>" }.joined() + "</ul></section>" }
        }
        if options.packing && !trip.packing.isEmpty {
            body += "<section><h2>要带</h2><ul class=\"pack\">" + trip.packing.map { "<li>\($0.done ? "☑" : "☐") \(h($0.text))</li>" }.joined() + "</ul></section>"
        }
        if options.prices && !trip.budget.isEmpty {
            body += "<section><h2>预算</h2><ul>" + trip.budget.map { "<li>\(h($0.item))：\($0.estimate.map(money) ?? "—")</li>" }.joined()
                + "<li><strong>合计：\(money(trip.budget.compactMap(\.estimate).reduce(0, +)))</strong></li></ul></section>"
        }
        return """
        <!doctype html>
        <html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(h(trip.title))</title>
        <style>
        :root { --bg:#fbfaf7; --fg:#1f2328; --muted:#5f6670; --card:#ffffff; --line:#e4e1da; --accent:#1d4ed8; }
        @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg:#16181c; --fg:#e8e6e3; --muted:#a3a8b0; --card:#1f2228; --line:#30343b; --accent:#7cb4ff; } }
        :root[data-theme="dark"] { --bg:#16181c; --fg:#e8e6e3; --muted:#a3a8b0; --card:#1f2228; --line:#30343b; --accent:#7cb4ff; }
        * { box-sizing:border-box; }
        body { margin:0; background:var(--bg); color:var(--fg); font:16px/1.55 -apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif; }
        main { max-width:680px; margin:0 auto; padding:24px 16px 48px; }
        h1 { font-size:28px; margin:0 0 4px; } h2 { font-size:18px; margin:0 0 10px; }
        .sub { margin:0; color:var(--muted); font-size:17px; } .meta { color:var(--muted); margin:6px 0 0; }
        section { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:16px; margin-top:16px; }
        .timeline { list-style:none; margin:0; padding:0; }
        .timeline li { display:flex; gap:12px; padding:8px 0; border-top:1px solid var(--line); }
        .timeline li:first-child { border-top:none; }
        .time { flex:0 0 96px; color:var(--accent); font-variant-numeric:tabular-nums; }
        .muted { color:var(--muted); font-size:14px; } .stay { margin:10px 0 0; }
        ul { margin:0; padding-left:20px; } .pack { list-style:none; padding:0; }
        footer { color:var(--muted); font-size:13px; text-align:center; margin-top:24px; }
        </style></head>
        <body><main>
        \(body)
        <footer>由 LifeOS 生成 · 行程有变化会更新这个页面</footer>
        </main></body></html>
        """
    }

    // MARK: - 工具

    public static func lodgingFor(_ day: TripDay, _ trip: Trip, _ calendar: Calendar) -> Lodging? {
        guard let date = day.date else { return nil }
        let d = calendar.startOfDay(for: date)
        return trip.lodging.first { l in
            guard let i = l.checkIn else { return false }
            return calendar.startOfDay(for: i) <= d && d < calendar.startOfDay(for: l.checkOut ?? i)
        }
    }

    public static func dateRange(_ trip: Trip, calendar: Calendar) -> String {
        guard trip.dated else { return "日期未定" }
        let n = trip.dayCount(calendar: calendar)
        if n <= 1 { return "\(md(trip.start, calendar)) \(weekday(trip.start, calendar))" }
        return "\(md(trip.start, calendar))–\(md(trip.end, calendar))，共 \(n) 天"
    }

    /// 正文小节里去掉 markdown 的行（只留列表项和普通句子，去掉加粗符号）
    public static func plainLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n").compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("|"), !t.hasPrefix(">") else { return nil }
            let clean = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
            return clean.hasPrefix("- ") ? clean : "- " + clean
        }
    }

    public static func md(_ d: Date, _ c: Calendar) -> String { "\(c.component(.month, from: d))/\(c.component(.day, from: d))" }
    public static func weekday(_ d: Date, _ c: Calendar) -> String { ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][c.component(.weekday, from: d) - 1] }
    static func money(_ v: Double) -> String { v == v.rounded() ? "$\(Int(v))" : String(format: "$%.2f", v) }

    static func ymd(_ d: Date, _ c: Calendar) -> String {
        String(format: "%04d%02d%02d", c.component(.year, from: d), c.component(.month, from: d), c.component(.day, from: d))
    }

    static func utc(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// 超过 75 字节的行折叠成多行（续行以空格开头），不拆开多字节字符
    static func fold(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var bytes = 0
        for ch in line {
            let n = String(ch).utf8.count
            if bytes + n > (out.isEmpty ? 75 : 74) {
                out.append(out.isEmpty ? current : " " + current)
                current = ""
                bytes = 0
            }
            current.append(ch)
            bytes += n
        }
        out.append(out.isEmpty ? current : " " + current)
        return out
    }

    static func h(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
