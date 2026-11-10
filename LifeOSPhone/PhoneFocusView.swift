import SwiftUI
import Charts
import LifeOSCore

/// 专注：没开始时选做什么、多久；进行中是倒计时圆环；下面是今天专注了多久、每一段、最近 7 天。
/// 记录在 `健康/专注/当天.md`（只有手机写），电脑上能看到。
struct PhoneFocusView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(FocusModel.self) private var focus

    var body: some View {
        @Bindable var focus = focus
        NavigationStack {
            List {
                switch focus.phase {
                case .idle: FocusSetup()
                case .focusing(let start, let end): FocusRunning(start: start, end: end)
                case .resting(let end): FocusResting(end: end)
                }
                FocusToday()
                FocusWeekChart()
                FocusLogSection()
            }
            .navigationTitle("专注")
            .toolbar { SettingsButton() }
            .refreshable { model.reload() }
            .safeAreaInset(edge: .bottom) { PhoneNoticeBanner() }
            .sheet(item: $focus.pending) { s in FocusDoneSheet(session: s) }
            #if DEBUG
            // 调试：`-debugFocus run` 启动时开始一段；`-debugFocus done` 开始后马上结束，打开“专注结束”
            .task {
                guard let mode = UserDefaults.standard.string(forKey: "debugFocus"), focus.phase == .idle else { return }
                focus.label = "线代：HW8"
                focus.start(now: Date().addingTimeInterval(-20 * 60))
                if mode == "done" { focus.finish() }
            }
            #endif
        }
    }
}

/// 离开判定的调试记录（`FocusLog`），默认收起；离开记错了的时候展开看是哪一步
private struct FocusLogSection: View {
    @State private var lines: [String] = []

    var body: some View {
        Section {
            DisclosureGroup("离开判定记录") {
                if lines.isEmpty {
                    Text("还没有记录").foregroundStyle(.secondary)
                }
                ForEach(Array(lines.reversed().prefix(60).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { lines = FocusLog.lines }
    }
}

/// 选做什么、多久
private struct FocusSetup: View {
    @Environment(PhoneModel.self) private var model
    @Environment(FocusModel.self) private var focus

    var body: some View {
        @Bindable var focus = focus
        Section("做什么") {
            TextField("比如：线代 HW8（可以不写）", text: $focus.label)
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Space.s) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { focus.label = s }
                                .buttonStyle(.bordered)
                                .tint(focus.label == s ? Color.accentColor : .secondary)
                                .font(.callout)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: Theme.Space.s, leading: Theme.Space.l, bottom: Theme.Space.s, trailing: Theme.Space.l))
            }
        }
        Section("多久") {
            Picker("分钟", selection: $focus.plannedMinutes) {
                ForEach(FocusModel.presets, id: \.self) { Text("\($0)").tag($0) }
                Text("正计时").tag(0)
            }
            .pickerStyle(.segmented)
            Stepper("结束后休息 \(focus.restMinutes) 分钟", value: $focus.restMinutes, in: 0...30)
        }
        Section {
            Button {
                focus.start()
            } label: {
                Label("开始专注", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        } footer: {
            Text("不会锁住别的 App。中途切出去超过 15 秒记一次“离开”，锁屏不算。到点在耳机里说一声。")
        }
    }

    /// 今天的时间窗、带时间的安排（课除外），再加最近用过的
    private var suggestions: [String] {
        let range = model.dayRange(model.clock)
        let today = model.occurrences(in: range)
            .filter { $0.style != .classSession && !$0.done }
            .map(\.title)
        let recent = model.focus.suffix(30).reversed().map(\.label).filter { !$0.isEmpty }
        var seen = Set<String>()
        return (today + recent).filter { seen.insert($0).inserted }.prefix(12).map { $0 }
    }
}

/// 进行中：圆环 + 剩余时间 + 几点结束
private struct FocusRunning: View {
    @Environment(FocusModel.self) private var focus
    let start: Date
    let end: Date?
    @State private var confirmDiscard = false

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let now = ctx.date
                let total = end.map { $0.timeIntervalSince(start) } ?? 0
                let elapsed = now.timeIntervalSince(start)
                VStack(spacing: Theme.Space.m) {
                    ZStack {
                        Circle().stroke(Color.accentColor.opacity(0.15), lineWidth: 14)
                        if total > 0 {
                            Circle().trim(from: 0, to: min(elapsed / total, 1))
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }
                        VStack(spacing: 4) {
                            Text(PodcastFmt.clock(end.map { max($0.timeIntervalSince(now), 0) } ?? elapsed))
                                .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                            Text(end.map { "\(Fmt.string($0, "H:mm")) 结束" } ?? "正计时")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 240, height: 240)
                    .accessibilityElement(children: .combine)
                    if !focus.label.isEmpty {
                        Text(focus.label).font(.headline).multilineTextAlignment(.center)
                    }
                    if focus.leaves > 0 {
                        Text("离开 \(focus.leaves) 次，共 \(Int((focus.leaveSeconds / 60).rounded())) 分钟")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.l)
            }
            HStack {
                Button("放弃", role: .destructive) { confirmDiscard = true }
                    .buttonStyle(.bordered)
                Spacer()
                Button(end == nil ? "结束" : "提前结束") { focus.finish() }
                    .buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            .confirmationDialog("放弃这一段？不会记下来。", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("放弃，不记", role: .destructive) { focus.discard() }
            }
        }
    }
}

private struct FocusResting: View {
    @Environment(FocusModel.self) private var focus
    let end: Date

    var body: some View {
        Section("休息") {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(PodcastFmt.clock(max(end.timeIntervalSince(ctx.date), 0)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(maxWidth: .infinity)
            }
            Button("结束休息") { focus.endRest() }
        }
    }
}

/// 结束后：写一句做了什么（可以不写）→ 存下
private struct FocusDoneSheet: View {
    @Environment(PhoneModel.self) private var model
    @Environment(FocusModel.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State var session: FocusSession
    @State private var confirmDrop = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("时间", value: "\(Fmt.string(session.start, "H:mm"))–\(Fmt.string(session.end, "H:mm"))")
                    LabeledContent("专注", value: "\(Int(session.minutes.rounded())) 分钟")
                    if session.leaves > 0 {
                        LabeledContent("离开", value: "\(session.leaves) 次，\(Int(session.leaveMinutes.rounded())) 分钟")
                    }
                }
                Section("做什么") { TextField("做什么", text: $session.label) }
                Section("做了什么（可以不写）") {
                    TextField("比如：写完 5B 最后一题", text: $session.note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    if focus.restMinutes > 0 {
                        Button("记下，休息 \(focus.restMinutes) 分钟") { save(rest: true) }
                    }
                    Button("记下") { save(rest: false) }
                    Button("不记", role: .destructive) { confirmDrop = true }
                }
            }
            .navigationTitle("专注结束")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("这一段不记了？", isPresented: $confirmDrop, titleVisibility: .visible) {
                Button("不记", role: .destructive) { focus.pending = nil }
            }
        }
        .interactiveDismissDisabled()
    }

    private func save(rest: Bool) {
        guard model.saveFocus(session) else { return }
        focus.pending = nil
        if rest { focus.startRest() }
    }
}

/// 今天专注了多久、每一段
private struct FocusToday: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let day = model.clock
        let today = model.focus.filter { model.calendar.isDate($0.start, inSameDayAs: day) }
        let total = today.reduce(0) { $0 + $1.minutes }
        Section {
            if today.isEmpty {
                Text("今天还没有专注记录。").foregroundStyle(.secondary)
            }
            ForEach(today.reversed()) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(s.label.isEmpty ? "没写做什么" : s.label).foregroundStyle(s.label.isEmpty ? .secondary : .primary)
                        Spacer()
                        Text("\(Int(s.minutes.rounded())) 分钟").monospacedDigit().foregroundStyle(.secondary)
                    }
                    let sub = ["\(Fmt.string(s.start, "H:mm"))–\(Fmt.string(s.end, "H:mm"))",
                               s.leaves > 0 ? "离开 \(s.leaves) 次" : "", s.note].filter { !$0.isEmpty }.joined(separator: " · ")
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            HStack {
                Text("今天")
                Spacer()
                Text(FocusFmt.duration(total)).monospacedDigit()
            }
        }
    }
}

/// 最近 7 天每天专注多少
private struct FocusWeekChart: View {
    @Environment(PhoneModel.self) private var model

    var body: some View {
        let cal = model.calendar
        let today = cal.startOfDay(for: model.clock)
        let days = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
        let data = days.map { ($0, FocusSummary.minutes(on: $0, in: model.focus, calendar: cal) / 60) }
        let counted = data.filter { $0.1 > 0 }
        Section {
            Chart(data, id: \.0) { d, h in
                BarMark(x: .value("日期", d, unit: .day), y: .value("小时", h))
                    .foregroundStyle(Color.accentColor)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) }
            }
            .frame(height: 140)
            .accessibilityLabel("最近 7 天每天专注的小时数")
        } header: {
            HStack {
                Text("最近 7 天")
                Spacer()
                if !counted.isEmpty {
                    Text("有记录的 \(counted.count) 天平均 \(FocusFmt.duration(counted.reduce(0) { $0 + $1.1 } * 60 / Double(counted.count)))")
                }
            }
        }
    }
}

enum FocusFmt {
    /// 95 → “1 小时 35 分”
    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) 分钟" }
        return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
    }
}
