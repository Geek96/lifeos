import AVKit
import SwiftUI
import LifeOSCore

/// 听：节目列表 → 一个节目的所有集 → 播放器。底部是迷你播放条，点开是完整播放器。
struct PhonePodcastView: View {
    @Environment(PodcastModel.self) private var podcast
    @State private var picking = false
    @State private var showingPlayer = false
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if podcast.root == nil {
                    PodcastSetupSection(picking: $picking)
                } else {
                    let resume = podcast.inProgress
                    if !resume.isEmpty {
                        Section("继续收听") {
                            ForEach(resume) { e in
                                PodcastEpisodeRow(episode: e, showName: true)
                            }
                        }
                    }
                    Section("节目") {
                        ForEach(podcast.shows) { show in
                            NavigationLink(value: show.id) {
                                PodcastShowRow(show: show)
                            }
                        }
                    }
                }
            }
            .navigationTitle("听")
            .navigationDestination(for: String.self) { id in
                if let show = podcast.shows.first(where: { $0.id == id }) { PodcastShowView(show: show) }
            }
            .toolbar {
                if podcast.root != nil {
                    Menu {
                        Button("重新扫描", systemImage: "arrow.clockwise") { podcast.reload() }
                        Button("换音频文件夹", systemImage: "folder") { picking = true }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("更多")
                }
                SettingsButton()
            }
            .refreshable { podcast.reload() }
            .safeAreaInset(edge: .bottom) {
                if podcast.current != nil { PodcastMiniPlayer(showingPlayer: $showingPlayer) }
            }
            .sheet(isPresented: $showingPlayer) { PodcastPlayerSheet() }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { podcast.choose(url) }
            }
            #if DEBUG
            // 调试：`-debugPodcastShow <节目>` 直接打开某个节目；再加 `-debugPodcastPlay 1` 放第一集并打开播放器
            .task {
                guard let id = UserDefaults.standard.string(forKey: "debugPodcastShow"),
                      let show = podcast.shows.first(where: { $0.id == id }) else { return }
                path = [id]
                if UserDefaults.standard.bool(forKey: "debugPodcastPlay"), let e = show.episodes.first {
                    podcast.play(e)
                    showingPlayer = true
                }
            }
            #endif
        }
    }
}

/// 还没选音频文件夹
private struct PodcastSetupSection: View {
    @Environment(PodcastModel.self) private var podcast
    @Binding var picking: Bool

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("选一个音频文件夹").font(.headline)
                Text("里面每个子文件夹是一个节目，音频文件是一集（比如 Möbius Sync 同步过来的“讲书”）。音频直接从手机里读，不用联网；进度只记在这台手机上。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("选文件夹") { picking = true }
                    .buttonStyle(.borderedProminent)
                if let e = podcast.setupError {
                    Text(e).font(.callout).foregroundStyle(Theme.orange)
                }
            }
            .padding(.vertical, Theme.Space.s)
        }
    }
}

private struct PodcastShowRow: View {
    @Environment(PodcastModel.self) private var podcast
    let show: PodcastShow

    var body: some View {
        let left = podcast.unplayedCount(show)
        VStack(alignment: .leading, spacing: 2) {
            Text(show.title).font(.body.weight(.medium))
            Text(left == 0 ? "\(show.episodes.count) 集 · 都听完了" : "\(show.episodes.count) 集 · \(left) 集没听完")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// 一个节目：所有集，可排序、隐藏听完的、批量标记
struct PodcastShowView: View {
    @Environment(PodcastModel.self) private var podcast
    let show: PodcastShow
    @AppStorage("podcastNewestFirst") private var newestFirst = false
    @AppStorage("podcastHidePlayed") private var hidePlayed = false

    var body: some View {
        // 重扫后用最新的节目内容
        let live = podcast.shows.first { $0.id == show.id } ?? show
        let ordered = newestFirst ? Array(live.episodes.reversed()) : live.episodes
        let shown = hidePlayed ? ordered.filter { !podcast.progress(of: $0).played } : ordered
        List {
            if shown.isEmpty {
                Text("都听完了").foregroundStyle(.secondary)
            }
            ForEach(shown) { e in PodcastEpisodeRow(episode: e, showName: false) }
        }
        .navigationTitle(live.title)
        .toolbar {
            Menu {
                Picker("顺序", selection: $newestFirst) {
                    Text("从第一集开始").tag(false)
                    Text("从最后一集开始").tag(true)
                }
                Toggle("隐藏听完的", isOn: $hidePlayed)
                Divider()
                Button("全部标为听完", systemImage: "checkmark.circle") { podcast.setPlayed(live.episodes, true) }
                Button("全部标为没听", systemImage: "circle") { podcast.setPlayed(live.episodes, false) }
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .accessibilityLabel("排序和筛选")
        }
        .refreshable { podcast.reload() }
    }
}

/// 一集：点一下播放（正在放的点一下暂停），左滑标记，长按更多
struct PodcastEpisodeRow: View {
    @Environment(PodcastModel.self) private var podcast
    let episode: PodcastEpisode
    let showName: Bool
    @State private var notes = false

    var body: some View {
        let p = podcast.progress(of: episode)
        let isCurrent = podcast.current?.id == episode.id
        Button {
            if isCurrent { podcast.toggle() } else { podcast.play(episode) }
        } label: {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: isCurrent && podcast.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(p.played && !isCurrent ? Color.secondary : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    if showName {
                        Text(episode.showID).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(episode.title)
                        .font(.body.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(p.played && !isCurrent ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    PodcastEpisodeMeta(episode: episode, progress: p, isCurrent: isCurrent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if p.played {
                Button("没听", systemImage: "circle") { podcast.setPlayed(episode, false) }
            } else {
                Button("听完", systemImage: "checkmark") { podcast.setPlayed(episode, true) }.tint(Theme.green)
            }
        }
        .contextMenu {
            Button("从头播放", systemImage: "backward.end") { podcast.play(episode, fromStart: true) }
            if p.played {
                Button("标为没听", systemImage: "circle") { podcast.setPlayed(episode, false) }
            } else {
                Button("标为听完", systemImage: "checkmark.circle") { podcast.setPlayed(episode, true) }
            }
            if episode.notesURL != nil {
                Button("看讲稿", systemImage: "doc.text") { notes = true }
            }
        }
        .sheet(isPresented: $notes) { PodcastNotesSheet(episode: episode) }
    }
}

/// 一集下面那行：时长 / 还剩多少 / 听完了，加一条进度
private struct PodcastEpisodeMeta: View {
    @Environment(PodcastModel.self) private var podcast
    let episode: PodcastEpisode
    let progress: PodcastProgress
    let isCurrent: Bool

    var body: some View {
        let total = podcast.duration(of: episode)
        let pos = isCurrent ? podcast.position : progress.position
        HStack(spacing: Theme.Space.s) {
            if progress.played && !isCurrent {
                Label("听完了", systemImage: "checkmark").labelStyle(.titleAndIcon)
            } else if let total, total > 0, pos >= 5 {
                ProgressView(value: min(pos / total, 1)).frame(width: 60)
                Text("还剩 \(PodcastFmt.minutes(total - pos))")
            } else if let total {
                Text(PodcastFmt.minutes(total))
            }
            if let d = episode.published {
                Text(Fmt.shortDay(d))
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

/// 底部迷你播放条
private struct PodcastMiniPlayer: View {
    @Environment(PodcastModel.self) private var podcast
    @Binding var showingPlayer: Bool

    var body: some View {
        if let e = podcast.current {
            HStack(spacing: Theme.Space.m) {
                Button { showingPlayer = true } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        ProgressView(value: podcast.duration > 0 ? min(podcast.position / podcast.duration, 1) : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开播放器：\(e.title)")
                Button { podcast.toggle() } label: {
                    Image(systemName: podcast.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(podcast.isPlaying ? "暂停" : "播放")
                Button { podcast.skip(PodcastModel.skipForward) } label: {
                    Image(systemName: "goforward.30").font(.title3).frame(width: 44, height: 44)
                }
                .accessibilityLabel("快进 30 秒")
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel))
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.xs)
        }
    }
}

/// 完整播放器
struct PodcastPlayerSheet: View {
    @Environment(PodcastModel.self) private var podcast
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?
    @State private var notes = false

    var body: some View {
        NavigationStack {
            if let e = podcast.current {
                ScrollView {
                    VStack(spacing: Theme.Space.xl) {
                        VStack(spacing: Theme.Space.s) {
                            Image(systemName: "waveform")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 160, height: 160)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
                                .accessibilityHidden(true)
                            Text(e.showID).font(.subheadline).foregroundStyle(.secondary)
                            Text(e.title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            if let c = podcast.currentChapter {
                                Text(c.title).font(.subheadline).foregroundStyle(Color.accentColor)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        scrubber
                        controls
                        options(e)
                        if !podcast.chapters.isEmpty { chapterList }
                        if let s = e.summary {
                            Text(s).font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Theme.Space.xl)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("收起")
                    }
                }
                .sheet(isPresented: $notes) { PodcastNotesSheet(episode: e) }
                #if DEBUG
                // 调试：`-debugPodcastNotes 1` 打开播放器后接着打开讲稿
                .task { if UserDefaults.standard.bool(forKey: "debugPodcastNotes") { notes = true } }
                #endif
            } else {
                Text("没有在放的").foregroundStyle(.secondary)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var scrubber: some View {
        let total = max(podcast.duration, 1)
        let shown = scrubbing ?? podcast.position
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...total) { editing in
                if !editing, let t = scrubbing {
                    podcast.seek(to: t)
                    scrubbing = nil
                }
            }
            .accessibilityLabel("播放位置")
            .accessibilityValue("\(PodcastFmt.clock(shown))，共 \(PodcastFmt.clock(podcast.duration))")
            HStack {
                Text(PodcastFmt.clock(shown))
                Spacer()
                Text("-" + PodcastFmt.clock(max(podcast.duration - shown, 0)))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// 上排：上一集 / 后退 15 / 播放 / 快进 30 / 下一集；有章节时下面再一排 上一章 / 下一章
    private var controls: some View {
        VStack(spacing: Theme.Space.l) {
            HStack(spacing: 28) {
                Button { podcast.previousEpisode() } label: { Image(systemName: "backward.fill") }
                    .font(.title2)
                    .disabled(!podcast.hasPreviousEpisode && podcast.position <= 5)
                    .accessibilityLabel("上一集")
                Button { podcast.skip(-PodcastModel.skipBack) } label: { Image(systemName: "gobackward.15") }
                    .accessibilityLabel("后退 15 秒")
                Button { podcast.toggle() } label: {
                    Image(systemName: podcast.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                }
                .accessibilityLabel(podcast.isPlaying ? "暂停" : "播放")
                Button { podcast.skip(PodcastModel.skipForward) } label: { Image(systemName: "goforward.30") }
                    .accessibilityLabel("快进 30 秒")
                Button { podcast.nextEpisode() } label: { Image(systemName: "forward.fill") }
                    .font(.title2)
                    .disabled(!podcast.hasNextEpisode)
                    .accessibilityLabel("下一集")
            }
            .font(.title)
            if !podcast.chapters.isEmpty {
                HStack(spacing: Theme.Space.xl) {
                    Button { podcast.previousChapter() } label: { Label("上一章", systemImage: "backward.end") }
                    Button { podcast.nextChapter() } label: { Label("下一章", systemImage: "forward.end") }
                        .disabled(podcast.chapterIndex == podcast.chapters.count - 1)
                }
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }

    private func options(_ e: PodcastEpisode) -> some View {
        @Bindable var podcast = podcast
        return HStack {
            Menu {
                Picker("倍速", selection: Binding(get: { podcast.rate }, set: { podcast.setRate($0) })) {
                    ForEach(PodcastModel.rates, id: \.self) { Text(PodcastFmt.rate($0)).tag($0) }
                }
            } label: {
                Text(PodcastFmt.rate(podcast.rate)).font(.body.weight(.semibold)).frame(minWidth: 52)
            }
            .accessibilityLabel("倍速 \(PodcastFmt.rate(podcast.rate))")
            Spacer()
            Menu {
                Button("关掉定时") { podcast.setSleep(.off) }
                ForEach([15, 30, 45, 60], id: \.self) { m in
                    Button("\(m) 分钟后") { podcast.setSleep(.at(Date().addingTimeInterval(Double(m) * 60))) }
                }
                Button("这一集放完") { podcast.setSleep(.endOfEpisode) }
            } label: {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Label(sleepText, systemImage: podcast.sleep == .off ? "moon.zzz" : "moon.zzz.fill")
                }
            }
            .accessibilityLabel("定时关闭")
            Spacer()
            if e.notesURL != nil {
                Button { notes = true } label: { Image(systemName: "doc.text") }
                    .accessibilityLabel("看讲稿")
                Spacer()
            }
            Menu {
                Picker("放完以后", selection: $podcast.playMode) {
                    ForEach(PodcastModel.PlayMode.allCases, id: \.self) { m in
                        Label(m.label, systemImage: m.systemImage).tag(m)
                    }
                }
                Toggle("自动接时跳过听完的", isOn: $podcast.skipPlayed)
                    .disabled(podcast.playMode == .stop || podcast.playMode == .loopOne)
            } label: {
                Image(systemName: podcast.playMode.systemImage)
            }
            .accessibilityLabel("放完以后：\(podcast.playMode.label)")
            Spacer()
            AirPlayButton().frame(width: 32, height: 32)
        }
        .font(.title3)
    }

    /// 章节列表：点一章跳到那里，正在放的那章高亮
    private var chapterList: some View {
        let now = podcast.chapterIndex
        return VStack(alignment: .leading, spacing: 0) {
            Text("章节").font(.headline).padding(.bottom, Theme.Space.s)
            ForEach(Array(podcast.chapters.enumerated()), id: \.offset) { i, c in
                Button { podcast.seek(to: c.start) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Text(PodcastFmt.clock(c.start))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .leading)
                        Text(c.title).font(.callout.weight(i == now ? .semibold : .regular))
                            .foregroundStyle(i == now ? Color.accentColor : Color.primary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if i == now {
                            Image(systemName: "speaker.wave.2.fill").font(.caption).foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, Theme.Space.s)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(c.title)，\(PodcastFmt.clock(c.start))")
                .accessibilityAddTraits(i == now ? .isSelected : [])
                if i < podcast.chapters.count - 1 { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sleepText: String {
        switch podcast.sleep {
        case .off: "定时"
        case .endOfEpisode: "本集完"
        case .at: PodcastFmt.clock(podcast.sleepRemaining ?? 0)
        }
    }
}

/// 讲稿：和音频同名的 .md，一段一段显示。记住每集看到第几段（存在手机本地），下次打开接着看；
/// 和章节同名的小标题可以点，点了音频跳到那一章。
struct PodcastNotesSheet: View {
    static let positionKey = "podcastNotesPosition"

    @Environment(PodcastModel.self) private var podcast
    @Environment(\.dismiss) private var dismiss
    let episode: PodcastEpisode
    @State private var blocks: [PodcastNotes.Block] = []
    @State private var chapters: [PodcastChapter] = []
    @State private var top: Int?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if loaded && blocks.isEmpty {
                    Text("没读到讲稿").foregroundStyle(.secondary).padding(Theme.Space.l)
                }
                LazyVStack(alignment: .leading, spacing: Theme.Space.m) {
                    ForEach(blocks) { b in
                        block(b).id(b.id)
                    }
                }
                .scrollTargetLayout()
                .padding(Theme.Space.l)
            }
            .scrollPosition(id: $top, anchor: .top)
            .navigationTitle("讲稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task { await load() }
        .onChange(of: top) { _, t in save(t) }
    }

    @ViewBuilder
    private func block(_ b: PodcastNotes.Block) -> some View {
        if b.level == 0 {
            Text(Self.inline(b.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let c = PodcastNotes.chapter(for: b, in: chapters) {
            let playing = podcast.current?.id == episode.id && podcast.currentChapter == c
            Button { podcast.play(episode, at: c.start) } label: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    Image(systemName: playing ? "speaker.wave.2.fill" : "play.circle")
                    Text(b.text).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text(PodcastFmt.clock(c.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .font(b.level == 1 ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(Color.accentColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Space.s)
            .accessibilityLabel("\(b.text)，从 \(PodcastFmt.clock(c.start)) 开始放")
        } else {
            Text(b.text)
                .font(b.level == 1 ? .title3.weight(.semibold) : .headline)
                .padding(.top, b.level == 1 ? 0 : Theme.Space.s)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func load() async {
        guard !loaded else { return }
        if let url = episode.notesURL, let raw = try? String(contentsOf: url, encoding: .utf8) {
            blocks = PodcastNotes.parse(raw)
        }
        let saved = (UserDefaults.standard.dictionary(forKey: Self.positionKey) as? [String: Int])?[episode.id]
        loaded = true
        // 讲稿改短了、记的那段已经没有了，就从头看
        if let saved, saved > 0, saved < blocks.count {
            try? await Task.sleep(for: .milliseconds(50))
            top = saved
        }
        chapters = podcast.current?.id == episode.id && !podcast.chapters.isEmpty
            ? podcast.chapters : await PodcastModel.chapters(of: episode.fileURL)
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

/// AirPlay / 蓝牙输出选择
private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

enum PodcastFmt {
    /// 1:02:05 / 12:05
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(max(t, 0).rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func minutes(_ t: TimeInterval) -> String {
        let m = Int((max(t, 0) / 60).rounded())
        return m >= 60 ? "\(m / 60) 小时 \(m % 60) 分" : "\(max(m, 1)) 分钟"
    }

    static func rate(_ r: Float) -> String {
        r == r.rounded() ? "\(Int(r))×" : String(format: "%g×", r)
    }
}
