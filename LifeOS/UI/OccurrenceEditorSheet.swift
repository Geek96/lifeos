import SwiftUI
import LifeOSCore

/// 只改重复事项里的这一次：时间（可以挪到另一天）、标题、地点、备注。写进 frontmatter 的 `exceptions`，重复规则不动。
struct OccurrenceEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let occurrence: Occurrence

    @State private var start = Date()
    @State private var end = Date()
    @State private var title = ""
    @State private var location = ""
    @State private var note = ""

    var body: some View {
        let item = model.item(for: occurrence)
        VStack(alignment: .leading, spacing: 0) {
            Form {
                if let series = occurrence.seriesStart {
                    Text("原本是 \(Fmt.day(series))\(timed ? " " + Fmt.time(series) : "") 的这一次。只改这一次，其余照常。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField("标题", text: $title)
                DatePicker(item?.kind == .window ? "从" : "开始", selection: $start,
                           displayedComponents: timed ? [.date, .hourAndMinute] : [.date])
                if hasEnd {
                    DatePicker(item?.kind == .window ? "到" : "结束", selection: $end, in: start...,
                               displayedComponents: timed ? [.date, .hourAndMinute] : [.date])
                }
                TextField("地点", text: $location, prompt: Text("可选"))
                TextField("备注", text: $note, prompt: Text("只属于这一次，比如“改到晚上”"))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("只改这一次") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || item == nil)
            }
            .padding()
        }
        .frame(width: 420)
        .onAppear(perform: load)
        .onChange(of: start) { old, new in
            // 改开始时保持时长
            if hasEnd { end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            if end < new { end = new }
        }
    }

    private var timed: Bool {
        guard let item = model.item(for: occurrence) else { return true }
        return item.startHasTime && item.kind != .window
    }

    private var hasEnd: Bool {
        guard let item = model.item(for: occurrence) else { return false }
        return (item.kind == .event && timed) || item.kind == .window
    }

    private func load() {
        start = occurrence.start
        end = occurrence.end ?? occurrence.start
        title = occurrence.title
        location = occurrence.location
        note = occurrence.note
    }

    /// 只写和系列不一样的字段
    private func save() {
        guard let item = model.item(for: occurrence), let series = occurrence.seriesStart else { return }
        let cal = model.calendar
        // 系列原本这一次的样子（不套例外）
        var plain = item
        plain.exceptions = []
        let original = Recurrence.occurrences(of: plain, in: DateInterval(start: cal.startOfDay(for: series), duration: 86400), calendar: cal)
            .first { $0.id == occurrence.id }
        var x = RecurrenceException(date: series)
        let s = timed ? start : cal.startOfDay(for: start)
        if s != (original?.start ?? series) { x.start = s }
        if hasEnd {
            // 时间窗的结束按天比较
            let e = timed ? end : cal.startOfDay(for: end)
            let o = original?.end.map { timed ? $0 : cal.startOfDay(for: $0) }
            let shifted = o.map { $0.addingTimeInterval(s.timeIntervalSince(original?.start ?? series)) }
            if e != shifted { x.end = e }
        }
        let t = title.trimmingCharacters(in: .whitespaces)
        if t != item.title { x.title = t }
        let l = location.trimmingCharacters(in: .whitespaces)
        if !l.isEmpty, l != item.location { x.location = l }
        let n = note.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { x.note = n }
        model.setException(x, for: occurrence, of: item,
                           message: x.isEmpty ? "这一次和系列一样" : "已保存：只改 \(Fmt.shortDay(series)) 这一次")
        dismiss()
    }
}
