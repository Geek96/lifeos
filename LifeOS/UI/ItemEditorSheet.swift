import SwiftUI
import LifeOSCore

/// 新建 / 编辑事项。字段随类型变化：约定（起止）、期限（截止时刻）、时间窗（起止日 + 大概要多久）。
struct ItemEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: AppModel.EditorRequest

    @State private var kind: LifeItem.Kind = .event
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var hasTime = true
    @State private var location = ""
    @State private var repeatChoice = RepeatChoice.none
    @State private var weekdays: Set<Int> = []
    @State private var hasUntil = false
    @State private var until = Date()
    @State private var estimate = 1.0
    @State private var remindDays = 3

    enum RepeatChoice: String, CaseIterable, Identifiable {
        case none = "不重复", daily = "每天", weekly = "每周", monthly = "每月", yearly = "每年"
        var id: String { rawValue }
    }

    private var isEditing: Bool { request.item != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Picker("类型", selection: $kind) {
                    ForEach(LifeItem.Kind.allCases, id: \.self) { k in Label(k.label, systemImage: k.systemImage).tag(k) }
                }
                .pickerStyle(.segmented)
                Text(kindHint).font(.caption).foregroundStyle(.secondary)

                TextField("标题", text: $title, prompt: Text("比如：看牙、续签 I-20、买菜"))

                switch kind {
                case .event:
                    Toggle("全天", isOn: Binding(get: { !hasTime }, set: { hasTime = !$0 }))
                    DatePicker("开始", selection: $start, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    if hasTime {
                        DatePicker("结束", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    }
                case .deadline:
                    Toggle("有具体时刻", isOn: $hasTime)
                    DatePicker("截止", selection: $start, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                    Stepper("提前 \(remindDays) 天提醒", value: $remindDays, in: 0...30)
                case .window:
                    DatePicker("从", selection: $start, displayedComponents: [.date])
                    DatePicker("到", selection: $end, in: start..., displayedComponents: [.date])
                    Stepper("大概要 \(Fmt.hours(estimate))", value: $estimate, in: 0.5...12, step: 0.5)
                }

                TextField("地点", text: $location, prompt: Text("可选"))

                Picker("重复", selection: $repeatChoice) {
                    ForEach(RepeatChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                if repeatChoice == .weekly {
                    HStack {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { d in
                            Toggle(["", "日", "一", "二", "三", "四", "五", "六"][d], isOn: Binding(
                                get: { weekdays.contains(d) },
                                set: { if $0 { weekdays.insert(d) } else { weekdays.remove(d) } }))
                            .toggleStyle(.button)
                        }
                    }
                }
                if repeatChoice != .none {
                    Toggle("重复到", isOn: $hasUntil)
                    if hasUntil { DatePicker("截止日期", selection: $until, displayedComponents: [.date]) }
                }
            }
            .formStyle(.grouped)

            HStack {
                if isEditing {
                    Text("准备信息（正文）不在这里改，在 Obsidian 里编辑或交给 agent。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "保存" : "放进日历") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 460)
        .onAppear(perform: load)
        .onChange(of: start) { old, new in
            // 改开始时间时保持时长
            if kind == .event { end = end.addingTimeInterval(new.timeIntervalSince(old)) }
            if end < new { end = new }
        }
    }

    private var kindHint: String {
        switch kind {
        case .event: return "约定：有具体时间要去的事。"
        case .deadline: return "期限：过了会出事的日子（续签、交税、退租）。"
        case .window: return "时间窗：这段时间内找空做就行，不催。"
        }
    }

    private func load() {
        let cal = model.calendar
        if let item = request.item {
            kind = item.kind
            title = item.title
            start = item.start
            end = item.end ?? item.start.addingTimeInterval(3600)
            hasTime = item.startHasTime
            location = item.location
            remindDays = item.remindDays
            estimate = item.estimateHours ?? 1
            if let until = item.repeatUntil { hasUntil = true; self.until = until }
            switch item.repeatRule {
            case .none: repeatChoice = .none
            case .daily: repeatChoice = .daily
            case .weekly(let d): repeatChoice = .weekly; weekdays = d
            case .monthly: repeatChoice = .monthly
            case .yearly: repeatChoice = .yearly
            }
        } else {
            kind = request.kind
            title = request.title
            start = request.start
            hasTime = kind != .window
            end = kind == .window ? (cal.date(byAdding: .day, value: 6, to: start) ?? start) : start.addingTimeInterval(3600)
        }
        until = hasUntil ? until : (cal.date(byAdding: .month, value: 3, to: start) ?? start)
    }

    private var repeatRule: RepeatRule? {
        switch repeatChoice {
        case .none: return nil
        case .daily: return .daily
        case .weekly: return .weekly(weekdays.isEmpty ? [model.calendar.component(.weekday, from: start)] : weekdays)
        case .monthly: return .monthly(model.calendar.component(.day, from: start))
        case .yearly: return .yearly
        }
    }

    private func save() {
        let cal = model.calendar
        let t = title.trimmingCharacters(in: .whitespaces)
        let timed = kind == .window ? false : hasTime
        let s = timed ? start : cal.startOfDay(for: start)
        let e: Date? = {
            switch kind {
            case .event: return timed ? end : nil
            case .window: return cal.startOfDay(for: end)
            case .deadline: return nil
            }
        }()
        if let item = request.item {
            var changes: [(String, String?)] = [
                ("kind", kind.rawValue), ("title", t),
                ("start", DateText.format(s, withTime: timed, calendar: cal)),
                ("end", e.map { DateText.format($0, withTime: kind == .event && timed, calendar: cal) }),
                ("all_day", kind == .event && !timed ? "true" : nil),
                ("location", location.isEmpty ? nil : location),
                ("repeat", repeatRule?.text),
                ("repeat_until", repeatRule != nil && hasUntil ? DateText.format(until, withTime: false, calendar: cal) : nil),
                ("remind_days", kind == .deadline && remindDays != 3 ? "\(remindDays)" : nil),
                ("estimate", kind == .window ? Fmt.estimateText(estimate) : nil),
            ]
            if kind == .event { changes.append(("done", nil)) }
            model.update(item, set: changes, message: "已保存：\(t)")
        } else {
            model.create(kind: kind, title: t, start: s, end: e, hasTime: timed, location: location,
                         repeatRule: repeatRule, estimate: kind == .window ? estimate : nil)
            // 新建后补上不在 createItem 参数里的字段
            if (kind == .deadline && remindDays != 3) || (repeatRule != nil && hasUntil),
               let created = model.items.first(where: { $0.title == t && $0.start == s }) {
                var extra: [(String, String?)] = []
                if kind == .deadline && remindDays != 3 { extra.append(("remind_days", "\(remindDays)")) }
                if repeatRule != nil && hasUntil { extra.append(("repeat_until", DateText.format(until, withTime: false, calendar: cal))) }
                try? model.store?.updateItem(at: created.fileURL, set: extra)
                model.reload()
            }
        }
        dismiss()
    }
}

extension Fmt {
    static func estimateText(_ h: Double) -> String {
        h == h.rounded() ? "\(Int(h))h" : String(format: "%.1fh", h)
    }
}
