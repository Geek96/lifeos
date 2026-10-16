import Foundation

/// 解析课程档案里的上课时间（自由文本），例如
/// "Tue/Thu 2:00–2:50pm"、"Mon/Wed 14:00–15:15"、"MWF 9:30–10:20 (A/GR) · MWF 11:00–11:50 (B)"。
/// 解析不出来（如“完全异步”）返回空。
public struct ClassMeeting: Hashable, Sendable {
    /// Calendar.weekday：1 = 周日 … 7 = 周六
    public var weekdays: Set<Int>
    /// 从当天 0 点起的分钟数
    public var startMinute: Int
    public var endMinute: Int
    /// 括号里的 section 标签（"A/GR" → ["A", "GR"]），没有则为空
    public var sections: [String]
}

public enum ClassSchedule {
    public static func parse(_ text: String) -> [ClassMeeting] {
        let segments = text.components(separatedBy: CharacterSet(charactersIn: "·;；\n"))
        return segments.compactMap(parseSegment)
    }

    /// 有 section 标签时只留下用户的 section；用户没设或所有段都没有标签时全保留。
    public static func meetings(_ text: String, section: String?) -> [ClassMeeting] {
        let all = parse(text)
        guard let section, !section.isEmpty, all.contains(where: { !$0.sections.isEmpty }) else { return all }
        let mine = all.filter { $0.sections.isEmpty || $0.sections.contains { $0.caseInsensitiveCompare(section) == .orderedSame } }
        return mine.isEmpty ? all : mine
    }

    private static let timeRegex = try! NSRegularExpression(
        pattern: #"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?\s*(?:[–—~\-]|to)\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#,
        options: [.caseInsensitive])
    private static let labelRegex = try! NSRegularExpression(pattern: #"\(([^)]*)\)"#)

    static func parseSegment(_ raw: String) -> ClassMeeting? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let ns = s as NSString
        guard let m = timeRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r).lowercased()
        }
        guard var h1 = group(1).flatMap(Int.init), var h2 = group(4).flatMap(Int.init) else { return nil }
        let m1 = group(2).flatMap(Int.init) ?? 0, m2 = group(5).flatMap(Int.init) ?? 0
        let suffix1 = group(3)?.first, suffix2 = group(6)?.first
        // 结束时间的 am/pm
        if suffix2 == "p", h2 < 12 { h2 += 12 }
        if suffix2 == "a", h2 == 12 { h2 = 0 }
        if suffix1 == "p", h1 < 12 { h1 += 12 }
        if suffix1 == "a", h1 == 12 { h1 = 0 }
        if suffix1 == nil {
            // 开始没写 am/pm：结束是下午且开始加 12 小时仍不晚于结束，就是下午
            if suffix2 == "p", h1 < 12, (h1 + 12) * 60 + m1 <= h2 * 60 + m2 { h1 += 12 }
            // 都没写：小于 7 点的按下午算（没人 2 点上早课）
            if suffix2 == nil, h1 < 7 { h1 += 12 }
        }
        if suffix2 == nil, h2 < 7 { h2 += 12 }
        let start = h1 * 60 + m1, end = h2 * 60 + m2
        guard end > start else { return nil }

        let dayText = ns.substring(to: m.range.location)
        let days = weekdays(in: dayText)
        guard !days.isEmpty else { return nil }

        var sections: [String] = []
        if let l = labelRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
            sections = ns.substring(with: l.range(at: 1)).split(separator: "/").map {
                $0.trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty }
        }
        return ClassMeeting(weekdays: days, startMinute: start, endMinute: end, sections: sections)
    }

    static func weekdays(in text: String) -> Set<Int> {
        let names: [(String, Int)] = [("sun", 1), ("mon", 2), ("tue", 3), ("wed", 4), ("thu", 5), ("fri", 6), ("sat", 7),
                                      ("周日", 1), ("周一", 2), ("周二", 3), ("周三", 4), ("周四", 5), ("周五", 6), ("周六", 7)]
        let lower = text.lowercased()
        let byName = Set(names.filter { lower.contains($0.0) }.map(\.1))
        if !byName.isEmpty { return byName }
        // 紧凑写法：MWF / TR / TTh / MW
        var result = Set<Int>()
        let letters = Array(text.filter { $0.isLetter })
        var i = 0
        while i < letters.count {
            let c = letters[i]
            let next = i + 1 < letters.count ? letters[i + 1] : nil
            switch c {
            case "M": result.insert(2)
            case "T":
                if next == "h" { result.insert(5); i += 1 } else { result.insert(3) }
            case "W": result.insert(4)
            case "R": result.insert(5)
            case "F": result.insert(6)
            case "S": result.insert(7)
            case "U": result.insert(1)
            default: return []   // 出现别的字母就不是紧凑写法
            }
            i += 1
        }
        return result
    }
}
