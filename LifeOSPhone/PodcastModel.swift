import AVFoundation
import MediaPlayer
import SwiftUI
import LifeOSCore

/// 听（`plugins.podcast`）：播放器 + 节目库 + 收听进度。
/// 音频文件夹单独选（和 vault 是两个 bookmark）：讲书这类音频通常不在 vault 下面。
/// 进度、倍速存在手机本地（UserDefaults），不写任何同步文件夹里的文件——手机版对 vault 只读的约定不变。
@Observable
@MainActor
final class PodcastModel {
    static let bookmarkKey = "podcastFolderBookmark"
    static let progressKey = "podcastProgress"
    static let rateKey = "podcastRate"
    static let skipBack: TimeInterval = 15
    static let skipForward: TimeInterval = 30
    static let rates: [Float] = [0.8, 1, 1.1, 1.25, 1.5, 1.75, 2]

    enum SleepTimer: Equatable {
        case off
        case at(Date)
        case endOfEpisode
    }

    // MARK: 节目库

    private(set) var root: URL?
    private(set) var shows: [PodcastShow] = []
    var setupError: String?
    private(set) var progress: [String: PodcastProgress] = [:]

    // MARK: 播放状态

    private(set) var current: PodcastEpisode?
    private(set) var isPlaying = false
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float
    private(set) var sleep: SleepTimer = .off
    /// 正在放的这集的章节（音频里没写章节时为空）
    private(set) var chapters: [PodcastChapter] = []

    /// 一集放完以后怎么接
    enum PlayMode: String, CaseIterable {
        case stop, sequence, loopAll, loopOne

        var label: String {
            switch self {
            case .stop: "放完就停"
            case .sequence: "顺序播放"
            case .loopAll: "列表循环"
            case .loopOne: "单集循环"
            }
        }

        var systemImage: String {
            switch self {
            case .stop: "stop.circle"
            case .sequence: "text.line.first.and.arrowtriangle.forward"
            case .loopAll: "repeat"
            case .loopOne: "repeat.1"
            }
        }
    }

    static let playModeKey = "podcastPlayMode"
    static let skipPlayedKey = "podcastSkipPlayed"

    var playMode: PlayMode {
        didSet { UserDefaults.standard.set(playMode.rawValue, forKey: Self.playModeKey) }
    }
    /// 自动接下一集时跳过已经听完的（手动按“下一集”永远是紧挨着的那集）
    var skipPlayed: Bool {
        didSet { UserDefaults.standard.set(skipPlayed, forKey: Self.skipPlayedKey) }
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastSaved = Date.distantPast

    init() {
        let saved = UserDefaults.standard.float(forKey: Self.rateKey)
        rate = saved > 0 ? saved : 1
        playMode = UserDefaults.standard.string(forKey: Self.playModeKey).flatMap(PlayMode.init) ?? .sequence
        skipPlayed = UserDefaults.standard.bool(forKey: Self.skipPlayedKey)
        if let data = UserDefaults.standard.data(forKey: Self.progressKey),
           let p = try? JSONDecoder().decode([String: PodcastProgress].self, from: data) {
            progress = p
        }
        setupRemoteCommands()
        observeInterruptions()
        // 组间休息 / 专注到点说话时：自己在放听书就临时调低听书，不去动音频会话
        AudioCue.shared.ownAudioPlaying = { [weak self] in self?.isPlaying ?? false }
        AudioCue.shared.duckOwnAudio = { [weak self] duck in self?.player?.volume = duck ? 0.2 : 1 }
    }

    // MARK: - 选文件夹

    func boot() {
        #if DEBUG
        // 模拟器调试：启动参数 `-debugPodcastPath <路径>` 直接读，不走文件选择
        if let path = UserDefaults.standard.string(forKey: "debugPodcastPath") {
            open(URL(fileURLWithPath: path), saveBookmark: false, scoped: false)
            return
        }
        #endif
        guard root == nil, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else {
            setupError = "之前选的音频文件夹找不到了，重新选一次"
            return
        }
        open(url, saveBookmark: stale)
    }

    func choose(_ url: URL) { open(url, saveBookmark: true) }

    private func open(_ url: URL, saveBookmark: Bool, scoped: Bool = true) {
        guard !scoped || url.startAccessingSecurityScopedResource() else {
            setupError = "没有权限读这个文件夹，重新选一次"
            return
        }
        let found = PodcastLibrary.scan(url)
        guard !found.isEmpty else {
            if scoped { url.stopAccessingSecurityScopedResource() }
            setupError = "这个文件夹里没找到音频（选放节目文件夹的那一层，比如“讲书”）"
            return
        }
        // 换文件夹时正在放的那集可能不在新文件夹里了
        if root != nil, root != url {
            stop()
            if scoped { root?.stopAccessingSecurityScopedResource() }
        }
        if saveBookmark, let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
        setupError = nil
        root = url
        shows = found
    }

    /// 回到前台、下拉时重扫：同步可能带来了新的集数
    func reload() {
        guard let root else { return }
        shows = PodcastLibrary.scan(root)
    }

    // MARK: - 查询

    func progress(of e: PodcastEpisode) -> PodcastProgress { progress[e.id] ?? PodcastProgress(duration: e.duration) }

    func duration(of e: PodcastEpisode) -> TimeInterval? { progress[e.id]?.duration ?? e.duration }

    /// 听了一部分的，最近听的在前
    var inProgress: [PodcastEpisode] {
        shows.flatMap(\.episodes)
            .filter { progress[$0.id]?.inProgress == true }
            .sorted { (progress[$0.id]?.updated ?? .distantPast) > (progress[$1.id]?.updated ?? .distantPast) }
    }

    func show(for e: PodcastEpisode) -> PodcastShow? { shows.first { $0.id == e.showID } }

    func unplayedCount(_ show: PodcastShow) -> Int { show.episodes.filter { progress[$0.id]?.played != true }.count }

    // MARK: - 播放

    func play(_ e: PodcastEpisode, fromStart: Bool = false) {
        if current?.id == e.id, !fromStart {
            resume()
            return
        }
        saveNow()
        prepareSession()
        var p = progress(of: e)
        if p.played || fromStart {
            p.position = 0
            p.played = false
        }
        let item = AVPlayerItem(url: e.fileURL)
        item.audioTimePitchAlgorithm = .timeDomain
        if let player {
            player.replaceCurrentItem(with: item)
        } else {
            let player = AVPlayer(playerItem: item)
            self.player = player
            timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished() }
        }
        current = e
        chapters = []
        loadChapters(e)
        position = p.position
        duration = p.duration ?? e.duration ?? 0
        progress[e.id] = p
        // 接着上次的位置往回退 3 秒，接上话头
        let start = max(p.position - 3, 0)
        player?.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        resume()
    }

    func resume() {
        guard let player else { return }
        prepareSession()
        player.defaultRate = rate
        player.playImmediately(atRate: rate)
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        saveNow()
        updateNowPlaying()
    }

    func toggle() { isPlaying ? pause() : resume() }

    func skip(_ seconds: TimeInterval) { seek(to: position + seconds) }

    /// 从某个时间开始放某一集（讲稿里点小标题跳到那一章）
    func play(_ e: PodcastEpisode, at t: TimeInterval) {
        if current?.id != e.id { play(e) }
        seek(to: t)
        if !isPlaying { resume() }
    }

    // MARK: - 章节

    var chapterIndex: Int? { PodcastChapter.index(at: position, in: chapters) }

    var currentChapter: PodcastChapter? { chapterIndex.map { chapters[$0] } }

    func nextChapter() {
        if let t = PodcastChapter.nextStart(from: position, in: chapters) { seek(to: t) }
    }

    func previousChapter() {
        if let t = PodcastChapter.previousStart(from: position, in: chapters) { seek(to: t) }
    }

    private func loadChapters(_ e: PodcastEpisode) {
        Task {
            let found = await Self.chapters(of: e.fileURL)
            if current?.id == e.id { chapters = found }
        }
    }

    /// 读 m4a 里的章节（QuickTime 章节轨，`synth.py` 用 ffmpeg 写的）
    nonisolated static func chapters(of url: URL) async -> [PodcastChapter] {
        let asset = AVURLAsset(url: url)
        guard let locale = try? await asset.load(.availableChapterLocales).first,
              let groups = try? await asset.loadChapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: [.commonKeyTitle])
        else { return [] }
        var out: [PodcastChapter] = []
        for g in groups {
            let item = AVMetadataItem.metadataItems(from: g.items, filteredByIdentifier: .commonIdentifierTitle).first ?? g.items.first
            let title = (try? await item?.load(.stringValue)) ?? nil
            let start = g.timeRange.start.seconds
            out.append(PodcastChapter(title: title ?? "第 \(out.count + 1) 章", start: start.isFinite ? start : 0))
        }
        return out.sorted { $0.start < $1.start }
    }

    func seek(to t: TimeInterval) {
        let limit = duration > 0 ? duration - 1 : t
        let target = min(max(t, 0), max(limit, 0))
        position = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
        saveNow()
    }

    func setRate(_ r: Float) {
        rate = r
        UserDefaults.standard.set(r, forKey: Self.rateKey)
        player?.defaultRate = r
        if isPlaying { player?.rate = r }
        updateNowPlaying()
    }

    func setSleep(_ s: SleepTimer) { sleep = s }

    /// 定时还剩多少秒（`.at` 时）
    var sleepRemaining: TimeInterval? {
        if case .at(let d) = sleep { return max(d.timeIntervalSinceNow, 0) }
        return nil
    }

    func stop() {
        saveNow()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        current = nil
        chapters = []
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - 标记

    func setPlayed(_ e: PodcastEpisode, _ played: Bool) {
        var p = progress(of: e)
        p.played = played
        p.position = 0
        p.updated = Date()
        progress[e.id] = p
        if current?.id == e.id, played { stop() }
        persist()
    }

    func setPlayed(_ episodes: [PodcastEpisode], _ played: Bool) {
        for e in episodes {
            var p = progress(of: e)
            p.played = played
            p.position = 0
            p.updated = Date()
            progress[e.id] = p
        }
        if let c = current, episodes.contains(where: { $0.id == c.id }), played { stop() }
        persist()
    }

    /// 同一节目里紧挨着的那一集；`wrap` 时最后一集的下一集是第一集
    func neighbor(of e: PodcastEpisode, offset: Int, wrap: Bool = false) -> PodcastEpisode? {
        guard let eps = show(for: e)?.episodes, let i = eps.firstIndex(where: { $0.id == e.id }) else { return nil }
        let j = i + offset
        if eps.indices.contains(j) { return eps[j] }
        guard wrap, !eps.isEmpty else { return nil }
        return eps[(j % eps.count + eps.count) % eps.count]
    }

    /// 放完一集后按播放模式接哪一集（`skipPlayed` 时跳过听完的；列表循环绕一圈都听完了就停）
    func autoNext(after e: PodcastEpisode) -> PodcastEpisode? {
        switch playMode {
        case .stop: return nil
        case .loopOne: return e
        case .sequence, .loopAll:
            guard let eps = show(for: e)?.episodes, let i = eps.firstIndex(where: { $0.id == e.id }) else { return nil }
            let wrap = playMode == .loopAll
            let order = wrap ? Array(eps[(i + 1)...] + eps[..<i]) : Array(eps[(i + 1)...])
            return skipPlayed ? order.first { progress[$0.id]?.played != true } : order.first
        }
    }

    var hasNextEpisode: Bool { current.flatMap { neighbor(of: $0, offset: 1, wrap: playMode == .loopAll) } != nil }
    var hasPreviousEpisode: Bool { current.flatMap { neighbor(of: $0, offset: -1, wrap: playMode == .loopAll) } != nil }

    /// 手动换集：紧挨着的那一集，听没听完都放（听完的从头放）
    func nextEpisode() {
        guard let e = current, let n = neighbor(of: e, offset: 1, wrap: playMode == .loopAll) else { return }
        play(n)
    }

    /// 上一集；这一集已经放了 5 秒以上先回到这一集开头（和音乐 App 一样）
    func previousEpisode() {
        guard let e = current else { return }
        if position > 5 {
            seek(to: 0)
            return
        }
        guard let p = neighbor(of: e, offset: -1, wrap: playMode == .loopAll) else { return }
        play(p)
    }

    // MARK: - 内部

    private func tick() {
        guard let player, let item = player.currentItem, current != nil else { return }
        let t = player.currentTime().seconds
        if t.isFinite { position = t }
        let d = item.duration.seconds
        if d.isFinite, d > 0, abs(d - duration) > 0.5 { duration = d }
        isPlaying = player.timeControlStatus != .paused
        if case .at(let end) = sleep, Date() >= end {
            sleep = .off
            pause()
            return
        }
        if Date().timeIntervalSince(lastSaved) > 5 { saveNow() }
    }

    private func finished() {
        guard let e = current else { return }
        var p = progress(of: e)
        p.played = true
        p.position = 0
        p.duration = duration > 0 ? duration : p.duration
        p.updated = Date()
        progress[e.id] = p
        persist()
        if sleep == .endOfEpisode {
            sleep = .off
            isPlaying = false
            updateNowPlaying()
            return
        }
        if let n = autoNext(after: e) {
            // 单集循环、或者接上的是听完的那集：play 里会从头放
            if n.id == e.id { current = nil }
            play(n)
        } else {
            isPlaying = false
            updateNowPlaying()
        }
    }

    /// 记下当前这集的位置；离结尾不到 `finishMargin` 秒就算听完
    func saveNow() {
        guard let e = current else { return }
        var p = progress(of: e)
        if duration > 0 { p.duration = duration }
        if duration > 0, position >= duration - PodcastProgress.finishMargin {
            p.played = true
        } else if position > 0 {
            p.position = position
        }
        p.updated = Date()
        progress[e.id] = p
        persist()
    }

    private func persist() {
        lastSaved = Date()
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: Self.progressKey)
        }
    }

    /// 每次开始放都重设一次：计时的语音提醒可能把会话改成了和别的 App 混着放
    private func prepareSession() {
        let s = AVAudioSession.sharedInstance()
        if s.category != .playback || s.routeSharingPolicy != .longFormAudio {
            try? s.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        }
        try? s.setActive(true)
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    self.isPlaying = false
                    self.saveNow()
                case .ended:
                    if options?.contains(.shouldResume) == true, self.current != nil { self.resume() }
                default: break
                }
            }
        }
    }

    // MARK: - 锁屏、控制中心、耳机

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBack)]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(-Self.skipBack) }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForward)]
        c.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(Self.skipForward) }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let t = e.positionTime
            Task { @MainActor in self?.seek(to: t) }
            return .success
        }
        c.changePlaybackRateCommand.supportedPlaybackRates = Self.rates.map { NSNumber(value: $0) }
        c.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackRateCommandEvent else { return .commandFailed }
            let r = e.playbackRate
            Task { @MainActor in self?.setRate(r) }
            return .success
        }
        // 耳机、锁屏上的“下一首 / 上一首”换集（和播放器上的换集键一样）
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.nextEpisode() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previousEpisode() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let e = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: e.title,
            MPMediaItemPropertyAlbumTitle: e.showID,
            MPMediaItemPropertyArtist: e.showID,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
