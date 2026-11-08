import SwiftUI
import AppKit
import LifeOSCore

/// 讲稿（听插件的电脑版）：只看讲稿，不放音频。左边是节目和每一集，右边一段一段显示和音频同名的 .md。
/// 音频文件夹默认是 `~/Desktop/SharedDocs/讲书`，可以换，路径存在 UserDefaults；每集看到第几段也存在本机，不写任何文件。
struct PodcastNotesView: View {
    static let folderKey = "podcastFolderPath"
    static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/SharedDocs/讲书")

    @AppStorage(PodcastNotesView.folderKey) private var folderPath = ""
    @State private var shows: [PodcastShow] = []
    /// 上次看的那一集，下次打开还停在这集
    @AppStorage("podcastNotesSelection") private var selection: PodcastEpisode.ID?
    @State private var loaded = false

    private var folder: URL? {
        if !folderPath.isEmpty { return URL(fileURLWithPath: folderPath) }
        return FileManager.default.fileExists(atPath: Self.defaultFolder.path) ? Self.defaultFolder : nil
    }

    private var selected: PodcastEpisode? {
        shows.lazy.flatMap(\.episodes).first { $0.id == selection }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                Text("讲稿").font(.largeTitle.bold())
                Spacer()
                if let folder {
                    Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Button("换文件夹…") { choose() }
                Button("刷新", systemImage: "arrow.clockwise") { scan() }
                    .labelStyle(.iconOnly)
                    .help("重新扫描文件夹")
            }
            if folder == nil {
                ContentUnavailableView {
                    Label("选一个音频文件夹", systemImage: "headphones")
                } description: {
                    Text("比如 SharedDocs/讲书/：每个子文件夹是一个节目，和音频同名的 .md 是讲稿。")
                } actions: {
                    Button("选择文件夹…") { choose() }.buttonStyle(.borderedProminent)
                }
            } else if loaded && shows.isEmpty {
                ContentUnavailableView("这个文件夹里没有音频", systemImage: "headphones",
                                       description: Text("每个子文件夹放音频和同名的 .md 讲稿。"))
            } else {
                HStack(alignment: .top, spacing: 0) {
                    List(selection: $selection) {
                        ForEach(shows) { show in
                            Section(show.title) {
                                ForEach(show.episodes) { e in
                                    Text(e.title)
                                        .lineLimit(2)
                                        .foregroundStyle(e.notesURL == nil ? .secondary : .primary)
                                        .tag(e.id)
                                        .help(e.notesURL == nil ? "这一集没有讲稿" : e.title)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(width: 260)
                    Divider()
                    if let e = selected {
                        PodcastNotesReader(episode: e).id(e.id)
                    } else {
                        ContentUnavailableView("选一集看讲稿", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .card(padding: 0)
            }
        }
        .padding(Theme.Space.xl)
        .task { if !loaded { scan() } }
    }

    private func scan() {
        guard let folder else { shows = []; loaded = true; return }
        shows = PodcastLibrary.scan(folder)
        loaded = true
        if selection == nil || selected == nil {
            selection = shows.first?.episodes.first(where: { $0.notesURL != nil })?.id
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        panel.message = "选择音频文件夹（比如 SharedDocs/讲书/）"
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        selection = nil
        scan()
    }
}

/// 一集的讲稿：`PodcastNotes.parse` 切好的段落；顶部有“目录”跳到二级标题，字号可调，记住看到第几段。
/// 自测 / 快问快答的答案先藏起来（`PodcastNotes.quizAnswers`），停顿行的位置换成“看答案”按钮
private struct PodcastNotesReader: View {
    static let positionKey = "podcastNotesPosition"

    let episode: PodcastEpisode
    @AppStorage("podcastNotesFontSize") private var fontSize = 15.0
    @AppStorage("podcastNotesShowAnswers") private var showAll = false
    @State private var blocks: [PodcastNotes.Block] = []
    /// 答案那段 → 这一题第一段答案
    @State private var answers: [Int: Int] = [:]
    /// 点开了的题（按第一段答案的 id）
    @State private var revealed: Set<Int> = []
    @State private var top: Int?
    @State private var loaded = false

    var body: some View {
        let headings = blocks.filter { $0.level == 2 }
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.m) {
                Text(episode.title).font(.headline).lineLimit(1)
                Spacer()
                if !headings.isEmpty {
                    Menu {
                        ForEach(headings) { h in Button(h.text) { top = h.id } }
                    } label: {
                        Label("目录", systemImage: "list.bullet")
                    }
                    .fixedSize()
                }
                if !answers.isEmpty {
                    Toggle("显示全部答案", isOn: $showAll)
                        .toggleStyle(.checkbox)
                        .fixedSize()
                }
                ControlGroup {
                    Button("小一点", systemImage: "textformat.size.smaller") { fontSize = max(12, fontSize - 1) }
                    Button("大一点", systemImage: "textformat.size.larger") { fontSize = min(24, fontSize + 1) }
                }
                .fixedSize()
                Button("播放音频", systemImage: "play.circle") { NSWorkspace.shared.open(episode.fileURL) }
                    .help("用默认的 App 打开音频")
                if let notes = episode.notesURL {
                    Button("在访达中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([notes]) }
                        .labelStyle(.iconOnly)
                        .help("在访达中显示讲稿")
                }
            }
            .padding(Theme.Space.m)
            Divider()
            ScrollView {
                if loaded && blocks.isEmpty {
                    Text(episode.notesURL == nil ? "这一集没有讲稿（没有和音频同名的 .md）。" : "没读到讲稿。")
                        .foregroundStyle(.secondary)
                        .padding(Theme.Space.xl)
                }
                LazyVStack(alignment: .leading, spacing: fontSize * 0.8) {
                    ForEach(blocks) { b in block(b).id(b.id) }
                }
                .scrollTargetLayout()
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.l)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: $top, anchor: .top)
        }
        .task { await load() }
        .onChange(of: top) { _, t in save(t) }
    }

    @ViewBuilder
    private func block(_ b: PodcastNotes.Block) -> some View {
        if PodcastNotes.isPause(b), answers[b.id + 1] == b.id + 1 {
            if !showAll { answerButton(b.id + 1) }
        } else if let g = answers[b.id], !showAll && !revealed.contains(g) {
            EmptyView()
        } else if PodcastNotes.isPause(b) {
            Text(b.text).font(.system(size: fontSize - 2)).foregroundStyle(.tertiary)
        } else {
            text(b)
        }
    }

    private func answerButton(_ g: Int) -> some View {
        let open = revealed.contains(g)
        return Button {
            if open { revealed.remove(g) } else { revealed.insert(g) }
        } label: {
            Label(open ? "收起答案" : "看答案", systemImage: open ? "eye.slash" : "eye")
                .font(.system(size: fontSize - 1))
        }
        .buttonStyle(.bordered)
        .tint(Theme.teal)
    }

    @ViewBuilder
    private func text(_ b: PodcastNotes.Block) -> some View {
        switch b.level {
        case 0:
            Text(Self.inline(b.text))
                .font(.system(size: fontSize))
                .lineSpacing(fontSize * 0.35)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case 1:
            Text(b.text)
                .font(.system(size: fontSize + 8, weight: .bold))
                .accessibilityAddTraits(.isHeader)
        default:
            Text(b.text)
                .font(.system(size: fontSize + 3, weight: .semibold))
                .foregroundStyle(Theme.teal)
                .padding(.top, fontSize * 0.8)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func load() async {
        guard !loaded else { return }
        if let url = episode.notesURL, let raw = try? String(contentsOf: url, encoding: .utf8) {
            blocks = PodcastNotes.parse(raw)
            answers = PodcastNotes.quizAnswers(in: blocks)
        }
        let saved = (UserDefaults.standard.dictionary(forKey: Self.positionKey) as? [String: Int])?[episode.id]
        loaded = true
        // 讲稿改短了、记的那段已经没有了，就从头看
        if let saved, saved > 0, saved < blocks.count {
            try? await Task.sleep(for: .milliseconds(50))
            top = saved
        }
    }

    private func save(_ t: Int?) {
        guard loaded, let t else { return }
        var all = (UserDefaults.standard.dictionary(forKey: Self.positionKey) as? [String: Int]) ?? [:]
        all[episode.id] = t
        UserDefaults.standard.set(all, forKey: Self.positionKey)
    }

    private static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}
