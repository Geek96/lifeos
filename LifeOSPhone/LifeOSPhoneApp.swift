import SwiftUI
import LifeOSCore

@main
struct LifeOSPhoneApp: App {
    @State private var model = PhoneModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(model)
                .task { model.boot() }
                // 没有文件监听：回到前台时重新读一次（同步可能在后台带来了新内容）
                .onChange(of: phase) { _, new in if new == .active { model.reload() } }
        }
    }
}

/// 三个分页：今天 / 日历 / 营养；还没选文件夹时先选
struct PhoneRootView: View {
    @Environment(PhoneModel.self) private var model
    // 调试时可用启动参数 `-debugTab 1` 直接打开某一页
    @State private var tab = UserDefaults.standard.integer(forKey: "debugTab")

    var body: some View {
        if model.vaultRoot == nil {
            PhoneSetupView()
        } else {
            TabView(selection: $tab) {
                Tab("今天", systemImage: "sun.max", value: 0) { PhoneTodayView() }
                Tab("日历", systemImage: "calendar", value: 1) { PhoneCalendarView() }
                if model.config.plugins.health {
                    Tab("营养", systemImage: "fork.knife", value: 2) { PhoneNutritionView() }
                }
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
            Text("手机上只看，不改。内容在电脑上定，通过 Möbius Sync 同步过来。")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label("在 Möbius Sync 里把文件夹设成“仅接收”", systemImage: "1.circle")
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
                    Text("手机版只读。要改内容，在电脑上改，或者跟 agent 说。")
                        .font(.footnote).foregroundStyle(.secondary)
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
