import SwiftUI
import LifeOSCore

/// 左栏：日历视图 / 收件箱 / 备忘；“图层”控制课程信息显示哪些；底部 CourseOS 联动状态与设置。
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.page) {
            Label("今天", systemImage: "sun.max").tag(AppModel.Page.today)
            Label("周", systemImage: "calendar.day.timeline.left").tag(AppModel.Page.week)
            Label("月", systemImage: "calendar").tag(AppModel.Page.month)

            Section("随手") {
                Label {
                    HStack {
                        Text("收件箱")
                        Spacer()
                        if !model.inbox.isEmpty {
                            Text("\(model.inbox.count)")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                                .tagCapsule(.secondary, horizontal: 7, vertical: 1)
                                .accessibilityLabel("\(model.inbox.count) 条未整理")
                        }
                    }
                } icon: { Image(systemName: "tray") }
                .tag(AppModel.Page.inbox)
                Label("备忘", systemImage: "note.text").tag(AppModel.Page.notes)
            }

            if model.config.plugins.health {
                Section("健康") {
                    Label("饮食", systemImage: "fork.knife").tag(AppModel.Page.diet)
                    Label("健身", systemImage: "figure.strengthtraining.traditional").tag(AppModel.Page.fitness)
                    Label("睡眠", systemImage: "bed.double").tag(AppModel.Page.sleep)
                }
            }

            if model.config.plugins.things || model.config.plugins.finance || model.config.plugins.travel || model.config.plugins.vision {
                Section("插件") {
                    if model.config.plugins.things {
                        Label("物品", systemImage: "shippingbox").tag(AppModel.Page.things)
                    }
                    if model.config.plugins.finance {
                        Label("消费", systemImage: "creditcard").tag(AppModel.Page.finance)
                    }
                    if model.config.plugins.travel {
                        Label("出行", systemImage: "airplane").tag(AppModel.Page.travel)
                    }
                    if model.config.plugins.vision {
                        Label("远景", systemImage: "mountain.2").tag(AppModel.Page.vision)
                    }
                }
            }

            Section("图层") {
                LayerToggle(title: "生活事项", style: .event, isOn: .constant(true), locked: true)
                LayerToggle(title: "上课", style: .classSession, isOn: Binding(
                    get: { model.config.layers.classes }, set: { model.setLayer(\.classes, $0) }))
                LayerToggle(title: "课程截止与考试", style: .courseExam, isOn: Binding(
                    get: { model.config.layers.courseDeadlines }, set: { model.setLayer(\.courseDeadlines, $0) }))
                LayerToggle(title: "课程活动与通知", style: .courseOptional, isOn: Binding(
                    get: { model.config.layers.courseOptional }, set: { model.setLayer(\.courseOptional, $0) }))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                CourseOSStatus()
                HStack {
                    Button {
                        model.newItem()
                    } label: {
                        Label("新建", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    SettingsLink { Image(systemName: "gearshape") }
                        .buttonStyle(.borderless)
                        .help("设置（⌘,）")
                        .accessibilityLabel("设置")
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

/// 图层行：色点 + 名称 + 勾选（像系统日历的日历列表）
struct LayerToggle: View {
    let title: String
    let style: Occurrence.Style
    @Binding var isOn: Bool
    var locked = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 6) {
                Circle().fill(Theme.tint(style)).frame(width: 8, height: 8)
                Text(title)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(locked)
        .help(locked ? "生活事项始终显示" : "在日历上显示或隐藏")
    }
}

/// CourseOS 联动状态：一行字，出错时变成提醒
struct CourseOSStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            if let error = model.courseError {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.orange)
                Text(error).lineLimit(2)
            } else if model.config.courseos.semester.isEmpty {
                Image(systemName: "link")
                Text("未连接 CourseOS")
            } else {
                Image(systemName: "graduationcap")
                Text("CourseOS · \(URL(fileURLWithPath: model.config.courseos.semester).lastPathComponent) · \(model.snapshot.courses.count) 门课")
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .help("只读：LifeOS 不会往 CourseOS 写任何东西。在设置里改学期目录。")
    }
}
