import SwiftUI
import LifeOSCore

/// 主窗口：左栏导航 / 中间日历 / 右栏检查器（与 CourseOS 同一套三栏）。
struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ContentView()
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        if model.page == .week || model.page == .month || model.page == .today {
                            Button { model.step(-1) } label: { Label("往前", systemImage: "chevron.left") }
                                .help("往前（⌘[）")
                            Button("今天") { model.anchor = Date() }
                                .help("回到今天（⌘T）")
                            Button { model.step(1) } label: { Label("往后", systemImage: "chevron.right") }
                                .help("往后（⌘]）")
                        }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Menu {
                            Button("约定") { model.newItem(kind: .event) }
                            Button("期限") { model.newItem(kind: .deadline) }
                            Button("时间窗") { model.newItem(kind: .window) }
                        } label: {
                            Label("新建", systemImage: "plus")
                        } primaryAction: {
                            model.newItem(kind: .event)
                        }
                        .help("新建约定（⌘N）；点箭头选期限或时间窗")
                        Button {
                            model.showInspector.toggle()
                        } label: {
                            Label(model.showInspector ? "隐藏检查器" : "显示检查器", systemImage: "sidebar.trailing")
                        }
                        .help("显示或隐藏右栏（⌥⌘I）")
                    }
                }
                .inspector(isPresented: $model.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 310, max: 360)
                }
        }
        .onChange(of: model.page) { model.selected = nil }
        .overlay(alignment: .bottom) {
            ToastView()
                .animation(.snappy, value: model.feedback.toast?.id)
        }
        .sheet(item: $model.editor) { request in
            ItemEditorSheet(request: request)
                .environment(model)
        }
        .frame(minWidth: 960, minHeight: 620)
    }
}

/// 中间内容随左栏切换；没选 vault 时引导选择。
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.vaultRoot == nil {
            ContentUnavailableView {
                Label("选择你的 LifeOS 文件夹", systemImage: "calendar.badge.plus")
            } description: {
                Text("LifeOS 把事项存成 Markdown 文件。")
            } actions: {
                Button("选择文件夹…") { model.chooseVault() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            switch model.page ?? .today {
            case .today: TodayView()
            case .week: WeekView()
            case .month: MonthView()
            case .inbox: InboxView()
            case .notes: NotesView()
            case .health: HealthView()
            case .things: ThingsView()
            case .finance: FinanceView()
            case .travel: TravelView()
            case .vision: VisionView()
            }
        }
    }
}
