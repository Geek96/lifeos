import SwiftUI
import LifeOSCore

/// 主窗口：左栏导航 / 中间日历 / 右栏检查器（与 CourseOS 同一套三栏）。
struct MainView: View {
    @Environment(AppModel.self) private var model

    /// 中间内容区最窄多少：留够换行的余地（日 / 周 / 月那排、记一晚、数字卡片在这个宽度下会折行）
    static let detailMinWidth: CGFloat = 480
    /// 窗口最窄：左栏 250 + 右栏 320 之后中间还有约 730，三栏边缘都留了余量。
    /// 1100 时三栏的理想宽度加起来放不下，系统先压左栏（压到比它的最小宽度还窄）
    static let windowMinWidth: CGFloat = 1320

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 240)
                .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 300)
        } detail: {
            ContentView()
                .frame(minWidth: Self.detailMinWidth)
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
                        if model.page?.isHealth != true || model.selected != nil {
                            Button {
                                model.showInspector.toggle()
                            } label: {
                                Label(model.showInspector ? "隐藏检查器" : "显示检查器", systemImage: "sidebar.trailing")
                            }
                            .help("显示或隐藏右栏（⌥⌘I）")
                        }
                    }
                }
                // 健康三页没选中东西时收起右栏，把宽度让给图表（点了训练事项照常打开）
                .inspector(isPresented: Binding(
                    get: { model.showInspector && (model.page?.isHealth != true || model.selected != nil) },
                    set: { model.showInspector = $0 })) {
                    InspectorView()
                        .frame(minWidth: 300)
                        .inspectorColumnWidth(min: 300, ideal: 320, max: 380)
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
        .frame(minWidth: Self.windowMinWidth, minHeight: 760)
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
            case .nutrition: NutritionView()
            case .fitness: FitnessView()
            case .rest: RestView()
            case .things: ThingsView()
            case .finance: FinanceView()
            case .travel: TravelView()
            case .vision: VisionView()
            }
        }
    }
}
