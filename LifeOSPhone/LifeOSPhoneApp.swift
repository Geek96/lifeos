import SwiftUI
import LifeOSCore

@main
struct LifeOSPhoneApp: App {
    @State private var model = PhoneModel()
    @State private var podcast = PodcastModel()
    @State private var focus = FocusModel()
    @State private var workout = WorkoutModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(model)
                .environment(podcast)
                .environment(focus)
                .environment(workout)
                .task {
                    model.boot()
                    PhoneUsage.observeLock()
                    model.phoneUsed()
                }
                // 专注、组间休息每秒看一次到没到点（计时期间 App 靠静音音频在后台活着，锁屏也会走）
                .task {
                    while !Task.isCancelled {
                        focus.tick()
                        workout.tick()
                        try? await Task.sleep(for: .seconds(1))
                    }
                }
                // 没有文件监听：回到前台时重新读一次（同步可能在后台带来了新内容）
                .onChange(of: phase) { old, new in
                    if new == .active {
                        model.reload()
                        podcast.reload()
                        focus.didReturn()
                        model.phoneUsed()
                    } else if new == .background {
                        // 进后台、被杀之前记下播到哪里
                        podcast.saveNow()
                        focus.didLeave()
                        model.phoneUsed()
                    }
                }
        }
    }
}

/// 分页：今天 / 日历 / 专注 / 营养（健康插件）/ 听（听插件）；还没选文件夹时先选
struct PhoneRootView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(PodcastModel.self) private var podcast
    @Environment(WorkoutModel.self) private var workout
    // 调试时可用启动参数 `-debugTab 1` 直接打开某一页
    @State private var tab = UserDefaults.standard.integer(forKey: "debugTab")

    var body: some View {
        if model.vaultRoot == nil {
            PhoneSetupView()
        } else {
            TabView(selection: $tab) {
                Tab("今天", systemImage: "sun.max", value: 0) { PhoneTodayView() }
                Tab("日历", systemImage: "calendar", value: 1) { PhoneCalendarView() }
                Tab("专注", systemImage: "timer", value: 4) { PhoneFocusView() }
                if model.config.plugins.health {
                    Tab("营养", systemImage: "fork.knife", value: 2) { PhoneNutritionView() }
                }
                if model.config.plugins.podcast {
                    Tab("听", systemImage: "headphones", value: 3) { PhonePodcastView() }
                }
            }
            .fullScreenCover(isPresented: Binding(get: { workout.presented }, set: { workout.presented = $0 })) { PhoneWorkoutView() }
            .task(id: model.config.plugins.podcast) {
                // 插件开着才去读音频文件夹；在电脑上关掉插件就停下正在放的
                if model.config.plugins.podcast { podcast.boot() } else { podcast.stop() }
            }
        }
    }
}

/// 第一次打开：在“文件”里选 Möbius Sync 同步过来的文件夹
struct PhoneSetupView: View {
    @Environment(PhoneModel.self) private var model
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("LifeOS").font(.largeTitle.bold())
            Text("内容在电脑上定，通过 Möbius Sync 同步过来。手机只会勾购物清单、记专注和训练、补记睡眠。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label("在 Möbius Sync 里把文件夹设成“发送和接收”（手机记的东西要同步回电脑）", systemImage: "1.circle")
                Label("点下面的按钮，在“文件”里选同步过来的文件夹", systemImage: "2.circle")
                Text("选 LifeOS vault 的上一级（比如 Obsidian），课程表也能一起读到。")
                    .font(.footnote).foregroundStyle(.secondary).padding(.leading, 28)
            }
            Button("选文件夹") { picking = true }
                .buttonStyle(.borderedProminent).controlSize(.large)
            if let error = model.setupError {
                Text(error).font(.callout).foregroundStyle(Theme.orange)
            }
            Spacer()
        }
        .padding(Theme.Space.xl)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.choose(url) }
        }
    }
}

/// 设置：换文件夹、看最后读取时间
struct PhoneSettingsSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false

    var body: some View {
        NavigationStack {
            List {
                Section("vault") {
                    LabeledContent("位置", value: model.vaultRoot?.lastPathComponent ?? "—")
                    if let t = model.lastLoad {
                        LabeledContent("最后读取", value: Fmt.string(t, "M月d日 H:mm"))
                    }
                    Button("重新读取") { model.reload() }
                    Button("换一个文件夹") { picking = true }
                }
                if let e = model.courseError {
                    Section("课程") { Text(e).foregroundStyle(.secondary) }
                }
                Section {
                    Text("手机只会勾购物清单、记专注（健康/专注/）、记训练（健康/训练记录/ 新建）、补记睡眠（健康/睡眠/ 里没记的那天）。别的要改，在电脑上改，或者跟 agent 说。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("在“快捷指令 → 自动化 → 新建 → App”里选你常用的 App，勾“已打开”和“已关闭”，选“立即运行”、关掉“运行时通知”，动作选 LifeOS 的“记一下用了手机”。早上第一次用手机时，LifeOS 按“晚上最后一次用 → 早上第一次用”补记昨晚的睡眠；那天已经记过的不动。")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("这 3 天记到的次数", value: "\(PhoneUsage.events.count)")
                } header: {
                    Text("自动记睡眠")
                }
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { model.choose(url) }
            }
        }
    }
}

/// 导航栏右上角的设置按钮
struct SettingsButton: View {
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: { Image(systemName: "gearshape") }
            .accessibilityLabel("设置")
            .sheet(isPresented: $showing) { PhoneSettingsSheet() }
    }
}
