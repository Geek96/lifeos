import SwiftUI
import AppKit
import LifeOSCore

/// LifeOS 入口：主窗口（三栏日历）+ 独立设置窗口（⌘,）。界面体系沿用 CourseOS。
@main
@MainActor
struct LifeOSApp: App {
    @State private var model = AppModel()
    @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.system.rawValue

    private var colorScheme: ColorScheme? { AppearanceChoice(rawValue: appearance)?.colorScheme }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(model)
                .preferredColorScheme(colorScheme)
                .task { model.boot() }
        }
        .defaultSize(width: 1360, height: 840)
        // 窗口不能拖得比 MainView 的最小宽高还小（否则三栏会互相挤压）
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 LifeOS") { AboutPanel.show() }
            }
            CommandGroup(replacing: .newItem) {
                Button("新建约定") { model.newItem(kind: .event) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("新建期限") { model.newItem(kind: .deadline) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("新建时间窗") { model.newItem(kind: .window) }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Divider()
                Button("记一笔到收件箱") {
                    model.page = .inbox
                    model.captureFocusRequest += 1
                }
                .keyboardShortcut("j", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("重新载入") { model.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button(model.showInspector ? "隐藏检查器" : "显示检查器") { model.showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
            }
            CommandMenu("前往") {
                Button("今天") { model.page = .today; model.anchor = Date() }
                    .keyboardShortcut("1", modifiers: .command)
                Button("周") { model.page = .week }
                    .keyboardShortcut("2", modifiers: .command)
                Button("月") { model.page = .month }
                    .keyboardShortcut("3", modifiers: .command)
                Button("收件箱") { model.page = .inbox }
                    .keyboardShortcut("4", modifiers: .command)
                Button("备忘") { model.page = .notes }
                    .keyboardShortcut("5", modifiers: .command)
                Divider()
                Button("回到今天") { model.anchor = Date() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("往前") { model.step(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                Button("往后") { model.step(1) }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(model)
                .preferredColorScheme(colorScheme)
        }
    }
}

extension AppModel {
    /// 周视图走一周、月视图走一个月、其他页走一天
    func step(_ n: Int) {
        let unit: Calendar.Component = page == .month ? .month : page == .week ? .weekOfYear : .day
        anchor = calendar.date(byAdding: unit, value: n, to: anchor) ?? anchor
    }
}

enum AboutPanel {
    @MainActor
    static func show() {
        let credits = NSMutableAttributedString(
            string: "学习之外的生活放在日历上：课表和课业由 CourseOS 叠上来，琐事交给你的 agent 准备。",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate()
    }
}
