import SwiftUI
import LifeOSCore

/// 备忘：查阅用的固定资料（证件到期、订阅、地址……），这里只列出来。
struct NotesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack {
                Text("备忘").font(.largeTitle.bold())
                Spacer()
                if let store = model.store {
                    Button("在访达中显示") { model.reveal(store.notesDir) }
                }
            }
            if model.notes.isEmpty {
                ContentUnavailableView("还没有备忘", systemImage: "note.text",
                                       description: Text("在 备忘/ 文件夹里放 Markdown 笔记，比如“证件与到期日”“订阅与账单”。"))
            } else {
                List(model.notes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(note.title).font(.headline)
                            Spacer()
                            Text(Fmt.shortDay(note.modified)).font(.caption).foregroundStyle(.secondary)
                        }
                        if !note.preview.isEmpty {
                            Text(note.preview).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.reveal(note.url) }
                    .contextMenu {
                        Button("在访达中显示") { model.reveal(note.url) }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
        .frame(maxWidth: .infinity)
    }
}
