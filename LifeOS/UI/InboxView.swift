import SwiftUI
import LifeOSCore

/// 收件箱：一句话记下来，之后交给 agent 整理成日历事项（agent 会先问你）。
struct InboxView: View {
    @Environment(AppModel.self) private var model
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("收件箱").font(.largeTitle.bold())
            HStack {
                TextField("随手记一句，比如“下周三前去银行改地址”", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(save)
                Button("记下", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            if model.inbox.isEmpty {
                ContentUnavailableView("收件箱是空的", systemImage: "tray",
                                       description: Text("想到什么就记在这里，不用分类、不用定时间。"))
            } else {
                List {
                    ForEach(model.inbox, id: \.self) { line in
                        HStack {
                            Text(line)
                            Spacer()
                            Button { model.removeInbox(line) } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary)
                                .help("移除这条").accessibilityLabel("移除")
                        }
                        .contextMenu {
                            Button("放进日历…") { model.editor = .init(item: nil, kind: .event, start: Insights.roundUpHour(model.clock, model.calendar), title: line) }
                            Button("移除") { model.removeInbox(line) }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                HStack {
                    Button {
                        model.handToAgent(model.agentPromptInbox())
                    } label: {
                        Label("交给 agent 整理（\(model.inbox.count) 条）", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("agent 会逐条问你，同意后才放进日历。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
        .onChange(of: model.captureFocusRequest) { focused = true }
    }

    private func save() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        model.capture(text)
        draft = ""
    }
}
