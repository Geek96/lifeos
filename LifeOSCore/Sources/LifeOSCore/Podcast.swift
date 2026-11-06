import Foundation

/// 听（`plugins.podcast`）：手机上的播客播放器。音频不在 vault 里，是用户在手机上另选的一个文件夹
/// （比如 Möbius Sync 同步过来的 `讲书/`）。这里只负责扫描文件夹、读订阅源里的标题和简介、算收听进度；
/// 播放和进度存储在手机 App 里（进度存在手机本地，不写任何文件）。
///
/// 文件夹约定（和 `讲书/README.md` 一致）：
/// - 选的文件夹下面每个子文件夹是一个节目，里面的音频文件是一集；选的文件夹本身有音频时，它自己也算一个节目
/// - 以 `.` 或 `_` 开头的文件夹和文件不算
/// - 和音频同名的 `.md` 是这一集的讲稿
/// - 节目文件夹或选的文件夹里的 `podcast.xml`（RSS）提供标题、简介、时长；没有就用文件名
public struct PodcastEpisode: Identifiable, Hashable, Sendable {
    /// `节目文件夹名/文件名`，进度按它存
    public var id: String
    public var showID: String
    public var title: String
    public var fileURL: URL
    /// 同名 `.md` 讲稿（没有就是 nil）
    public var notesURL: URL?
    public var summary: String?
    public var published: Date?
    /// 订阅源里写的时长（秒）；没写时播放后由 App 记下实际时长
    public var duration: TimeInterval?
}

public struct PodcastShow: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var folder: URL
    /// 按文件名排（`localizedStandardCompare`，01、02…10 的顺序对）
    public var episodes: [PodcastEpisode]
}

/// 一集的收听进度（存在手机本地）
public struct PodcastProgress: Codable, Equatable, Sendable {
    public var position: TimeInterval
    public var duration: TimeInterval?
    public var played: Bool
    public var updated: Date

    public init(position: TimeInterval = 0, duration: TimeInterval? = nil, played: Bool = false, updated: Date = Date()) {
        self.position = position
        self.duration = duration
        self.played = played
        self.updated = updated
    }

    /// 0…1；不知道时长时为 nil
    public var fraction: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    /// 听了一部分、还没听完
    public var inProgress: Bool { !played && position >= 5 }

    /// 离结尾不到这么多秒就算听完（片尾不用硬听完）
    public static let finishMargin: TimeInterval = 20
}

/// 一集里的一章：讲书的 m4a 由 `synth.py` 按讲稿的 `## ` 小标题写入章节，App 用 AVFoundation 读出来
public struct PodcastChapter: Hashable, Sendable {
    public var title: String
    /// 开始时间（秒）
    public var start: TimeInterval

    public init(title: String, start: TimeInterval) {
        self.title = title
        self.start = start
    }

    /// 这个位置在第几章；没有章节时为 nil。差一点点就到下一章时（刚跳过去、还没走到）也算下一章
    public static func index(at t: TimeInterval, in chapters: [PodcastChapter]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        return chapters.lastIndex { $0.start <= t + 0.5 } ?? 0
    }

    /// 下一章的开始时间；已经是最后一章时为 nil
    public static func nextStart(from t: TimeInterval, in chapters: [PodcastChapter]) -> TimeInterval? {
        guard let i = index(at: t, in: chapters), i + 1 < chapters.count else { return nil }
        return chapters[i + 1].start
    }

    /// “上一章”：这一章已经放了 3 秒以上就回到这一章开头，否则到上一章开头（和音乐 App 的上一首一样）
    public static func previousStart(from t: TimeInterval, in chapters: [PodcastChapter]) -> TimeInterval? {
        guard let i = index(at: t, in: chapters) else { return nil }
        if i == 0 || t - chapters[i].start > 3 { return chapters[i].start }
        return chapters[i - 1].start
    }
}

/// 讲稿（和音频同名的 .md）按段落切开，手机上一段一段显示，好记住看到哪一段、小标题能跳到对应的章节
public enum PodcastNotes {
    public struct Block: Identifiable, Hashable, Sendable {
        /// 第几段（从 0 开始），记阅读位置用
        public var id: Int
        /// 标题级别：`# ` 是 1、`## ` 是 2；普通段落是 0
        public var level: Int
        /// 标题去掉 `#` 后的文字；普通段落原样保留（行内 markdown 交给界面渲染）
        public var text: String
    }

    public static func parse(_ raw: String) -> [Block] {
        var body = raw.replacingOccurrences(of: "\r\n", with: "\n")
        // 去掉开头的 frontmatter
        if body.hasPrefix("---\n"), let end = body.range(of: "\n---", range: body.index(body.startIndex, offsetBy: 4)..<body.endIndex) {
            body = String(body[end.upperBound...])
            if let nl = body.firstIndex(of: "\n") { body = String(body[body.index(after: nl)...]) } else { body = "" }
        }
        var out: [Block] = []
        for chunk in body.components(separatedBy: "\n").split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let text = chunk.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let hashes = text.prefix { $0 == "#" }.count
            if hashes > 0, text.dropFirst(hashes).first == " " {
                out.append(Block(id: out.count, level: hashes, text: text.dropFirst(hashes).trimmingCharacters(in: .whitespaces)))
            } else {
                out.append(Block(id: out.count, level: 0, text: text))
            }
        }
        return out
    }

    /// 和这个小标题同名的章节（`synth.py` 用 `## ` 后面的文字当章节名）
    public static func chapter(for block: Block, in chapters: [PodcastChapter]) -> PodcastChapter? {
        guard block.level >= 2 else { return nil }
        return chapters.first { $0.title == block.text }
    }
}

public enum PodcastLibrary {
    public static let audioExtensions: Set<String> = ["m4a", "mp3", "m4b", "aac", "wav", "aif", "aiff", "caf", "flac"]

    /// 扫描选的文件夹
    public static func scan(_ root: URL) -> [PodcastShow] {
        let fm = FileManager.default
        let feeds = loadFeeds(at: root)
        var shows: [PodcastShow] = []
        if let own = show(at: root, feeds: feeds, fm: fm) { shows.append(own) }
        let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        for dir in children where !dir.lastPathComponent.hasPrefix("_")
            && (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let local = feeds.merging(loadFeeds(at: dir)) { _, new in new }
            if let s = show(at: dir, feeds: local, fm: fm) { shows.append(s) }
        }
        return shows.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func show(at dir: URL, feeds: [String: FeedItem], fm: FileManager) -> PodcastShow? {
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let showID = dir.lastPathComponent
        let audio = files
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) && !$0.lastPathComponent.hasPrefix("_") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        guard !audio.isEmpty else { return nil }
        let episodes = audio.map { url -> PodcastEpisode in
            let name = url.lastPathComponent
            let item = feeds["\(showID)/\(name)"] ?? feeds[name]
            let notes = url.deletingPathExtension().appendingPathExtension("md")
            return PodcastEpisode(
                id: "\(showID)/\(name)",
                showID: showID,
                title: item.map { displayTitle($0.title, show: showID) } ?? url.deletingPathExtension().lastPathComponent,
                fileURL: url,
                notesURL: fm.fileExists(atPath: notes.path) ? notes : nil,
                summary: item?.summary,
                published: item?.published,
                duration: item?.duration
            )
        }
        return PodcastShow(id: showID, title: showID, folder: dir, episodes: episodes)
    }

    /// 订阅源标题常带节目名前缀（`HIST2112 · 第十周文献 …`），列表里已经在节目下面了，去掉
    static func displayTitle(_ title: String, show: String) -> String {
        let prefix = "\(show) · "
        let t = title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
        return t.trimmingCharacters(in: .whitespaces).isEmpty ? title : t
    }

    // MARK: - 订阅源

    struct FeedItem: Equatable {
        var title: String
        var summary: String?
        var published: Date?
        var duration: TimeInterval?
    }

    /// 读一个文件夹里的 `podcast.xml`，按 `节目/文件名` 和 `文件名` 两种键索引
    static func loadFeeds(at dir: URL) -> [String: FeedItem] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("podcast.xml")) else { return [:] }
        return parseFeed(data)
    }

    static func parseFeed(_ data: Data) -> [String: FeedItem] {
        let reader = FeedReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        var out: [String: FeedItem] = [:]
        for (path, item) in reader.items {
            let parts = path.split(separator: "/").map(String.init)
            guard let file = parts.last else { continue }
            if parts.count >= 2 { out["\(parts[parts.count - 2])/\(file)"] = item }
            if out[file] == nil { out[file] = item }
        }
        return out
    }

    /// `00:27:22`、`27:22` 或秒数
    static func parseDuration(_ s: String) -> TimeInterval? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + $1! }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.date(from: s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 只拿 item 里的 title / description（或 itunes:summary）/ pubDate / itunes:duration / enclosure url
    private final class FeedReader: NSObject, XMLParserDelegate {
        var items: [(String, FeedItem)] = []
        private var inItem = false
        private var text = ""
        private var fields: [String: String] = [:]
        private var enclosure: String?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            text = ""
            if name == "item" { inItem = true; fields = [:]; enclosure = nil }
            if inItem, name == "enclosure", let url = attributes["url"] { enclosure = url }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

        func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            guard inItem else { return }
            if name == "item" {
                inItem = false
                guard let enclosure, let url = URL(string: enclosure) else { return }
                let item = FeedItem(
                    title: fields["title"] ?? url.deletingPathExtension().lastPathComponent,
                    summary: fields["description"] ?? fields["itunes:summary"],
                    published: fields["pubDate"].flatMap(PodcastLibrary.parseDate),
                    duration: fields["itunes:duration"].flatMap(PodcastLibrary.parseDuration)
                )
                // url.path 已经解码了百分号
                items.append((url.path, item))
            } else {
                let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty, fields[name] == nil { fields[name] = value }
            }
        }
    }
}
