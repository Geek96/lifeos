import AVFoundation
import UserNotifications

/// 计时（专注、组间休息）用的声音：
/// - `KeepAlive`：计时期间放一段听不见的静音，让 App 锁屏后也一直活着（`UIBackgroundModes: audio`），
///   这样到点能在耳机里说话、也能知道什么时候锁屏。和别的 App 的音乐混着放，不打断它们。
/// - `Speaker`：到点用语音提醒（中文）。说话时把别的 App 的声音压低（duck），说完恢复；
///   LifeOS 自己在放听书时改成临时调低听书的音量。
/// 系统提示音会被静音键关掉，所以提醒都用语音。
@MainActor
final class AudioCue: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AudioCue()

    private let engine = AVAudioEngine()
    private let silence = AVAudioPlayerNode()
    private let synth = AVSpeechSynthesizer()
    private var holders: Set<String> = []
    /// 说话时临时调低 / 恢复 LifeOS 自己正在放的听书（PodcastModel 设）
    var duckOwnAudio: ((Bool) -> Void)?
    /// LifeOS 自己在放听书：这时不动 AVAudioSession 的设置
    var ownAudioPlaying: () -> Bool = { false }

    override init() {
        super.init()
        synth.delegate = self
        engine.attach(silence)
        let format = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(silence, to: engine.mainMixerNode, format: format)
        observeInterruptions()
    }

    /// 静音被打断（来电、Siri、耳机插拔、别的 App 改了音频设置）引擎就停了，App 在后台会被挂起；
    /// 打断结束、设备变了、音频服务重置后，还在计时就重新放
    private func observeInterruptions() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                FocusLog.add(began ? "音频被打断" : "音频打断结束")
                if !began { self.resumeSilence() }
            }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            MainActor.assumeIsolated {
                FocusLog.add("音频设备变了")
                self.resumeSilence()
            }
        }
        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                FocusLog.add("音频服务重置")
                self.resumeSilence()
            }
        }
    }

    private func resumeSilence() {
        guard !holders.isEmpty else { return }
        configure(duck: false)
        startSilence()
        FocusLog.add(engine.isRunning ? "静音重新放了" : "静音没放起来")
    }

    /// 引擎没在跑就启动；放静音的节点没在放就重新排上一秒全 0 的循环
    private func startSilence() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else { return }
        buffer.frameLength = buffer.frameCapacity  // 全 0：静音
        do {
            if !engine.isRunning { try engine.start() }
            if !silence.isPlaying {
                silence.scheduleBuffer(buffer, at: nil, options: .loops)
                silence.play()
            }
        } catch {
            // 起不来就只靠本地通知
        }
    }

    // MARK: - 保持后台运行

    /// `who` 用来区分专注和训练：两边都停了才真的停
    func hold(_ who: String) {
        holders.insert(who)
        guard !engine.isRunning else { return }
        configure(duck: false)
        startSilence()
    }

    func release(_ who: String) {
        holders.remove(who)
        guard holders.isEmpty, engine.isRunning else { return }
        silence.stop()
        engine.stop()
        if !ownAudioPlaying() {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func configure(duck: Bool) {
        guard !ownAudioPlaying() else { return }
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: duck ? [.mixWithOthers, .duckOthers] : [.mixWithOthers])
        try? s.setActive(true)
    }

    // MARK: - 语音

    func say(_ text: String) {
        if ownAudioPlaying() {
            duckOwnAudio?(true)
        } else {
            // 加上 duckOthers 再激活一次，别的 App 的音乐就会被压低
            configure(duck: true)
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.speak(u)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedSpeaking() }
    }

    private func finishedSpeaking() {
        guard !synth.isSpeaking else { return }
        if ownAudioPlaying() {
            duckOwnAudio?(false)
            return
        }
        // 去掉 duck：要先停用再激活，别的 App 的音量才会回来
        let running = engine.isRunning
        if running { engine.pause() }
        let s = AVAudioSession.sharedInstance()
        try? s.setActive(false, options: .notifyOthersOnDeactivation)
        if running || !holders.isEmpty {
            configure(duck: false)
            try? engine.start()
        }
    }

    // MARK: - 本地通知（App 被系统杀掉时的后备）

    static func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notify(_ id: String, at date: Date, title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        let t = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: t))
    }

    static func cancel(_ id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
