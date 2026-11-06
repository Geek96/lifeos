import SwiftUI
import LifeOSCore

/// 今天页里的“今天练什么”：训练计划里今天的动作和这次建议的重量，点“开始训练”进训练页
struct PhoneTrainingSection: View {
    @Environment(PhoneModel.self) private var model
    @Environment(WorkoutModel.self) private var workout
    @State private var choosing = false

    var body: some View {
        let plan = model.health.plan
        let today = WorkoutModel.planDay(plan, on: model.clock, calendar: model.calendar)
        Section {
            if workout.isActive {
                Button { workout.presented = true } label: {
                    Label("回到训练：\(workout.title)（已做 \(workout.done.count) 组）", systemImage: "figure.strengthtraining.traditional")
                }
            } else if let today {
                let items = WorkoutModel.items(for: today, exercises: model.health.exercises)
                ForEach(items) { item in
                    HStack {
                        Text(item.name)
                        Spacer()
                        Text(WorkoutRow.target(item)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
                Button {
                    workout.begin(title: today.what, items: items)
                    workout.presented = true
                } label: {
                    Label("开始训练", systemImage: "play.fill")
                }
                .disabled(items.isEmpty)
            } else {
                Text("今天计划里没有力量训练。").foregroundStyle(.secondary)
            }
            if !workout.isActive, !plan.days.isEmpty {
                Button("练别的一天…") { choosing = true }
                    .font(.callout)
            }
        } header: {
            Text(today.map { "今天练什么 · \($0.what)" } ?? "今天练什么")
        }
        .confirmationDialog("按哪一天的计划练？", isPresented: $choosing, titleVisibility: .visible) {
            ForEach(plan.days.filter { !WorkoutModel.items(for: $0, exercises: model.health.exercises).isEmpty }) { d in
                Button("\(d.weekday) · \(d.what)") {
                    workout.begin(title: d.what, items: WorkoutModel.items(for: d, exercises: model.health.exercises))
                    workout.presented = true
                }
            }
        }
        #if DEBUG
        // 调试：`-debugWorkout 1` 启动时按今天（或计划第一天）开始一次训练并打开训练页；`-debugWorkout rest` 再做完一组（没做满）进入休息
        .task {
            guard let mode = UserDefaults.standard.string(forKey: "debugWorkout"), !workout.isActive,
                  let d = today ?? plan.days.first(where: { !$0.exercises.isEmpty }) else { return }
            workout.begin(title: d.what, items: WorkoutModel.items(for: d, exercises: model.health.exercises))
            if mode == "rest" { workout.completeSet(reps: (workout.currentItem?.reps ?? 10) - 2) }
            workout.presented = true
        }
        #endif
    }
}

/// 训练页：当前动作（重量、次数、做完这组）→ 休息倒计时 → 全部动作和做过的组 → 练完存下
struct PhoneWorkoutView: View {
    @Environment(PhoneModel.self) private var model
    @Environment(WorkoutModel.self) private var workout
    @Environment(\.dismiss) private var dismiss
    @State private var reps: Double = 10
    @State private var finishing = false
    @State private var note = ""
    @State private var confirmDiscard = false

    var body: some View {
        @Bindable var workout = workout
        NavigationStack {
            List {
                if let r = workout.rest {
                    restSection(r)
                }
                if let item = workout.currentItem {
                    currentSection(item)
                }
                Section("全部动作") {
                    ForEach(Array(workout.items.enumerated()), id: \.offset) { i, item in
                        Button { workout.current = i } label: { WorkoutRow(item: item, sets: workout.setsDone(item), isCurrent: i == workout.current) }
                            .buttonStyle(.plain)
                    }
                }
                Section {
                    Toggle("耳机里语音提醒", isOn: $workout.voice)
                    if !workout.done.isEmpty {
                        Button("撤销上一组") { workout.undoLast() }
                    }
                } footer: {
                    Text("休息时长按动作来：大重量的 2 分半，其他 1 分半；休息时按 ±15 秒，下次这个动作就用调过的。上一组没做满，多休息 30 秒。")
                }
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }.accessibilityLabel("收起，训练继续")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("练完") { finishing = true }
                }
            }
            .safeAreaInset(edge: .bottom) { PhoneNoticeBanner() }
            .onChange(of: workout.current, initial: true) { _, _ in reps = workout.currentItem?.reps ?? 10 }
            .sheet(isPresented: $finishing) { finishSheet }
        }
    }

    private func restSection(_ r: WorkoutModel.Rest) -> some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(spacing: Theme.Space.s) {
                    Text("休息").font(.subheadline).foregroundStyle(.secondary)
                    Text(PodcastFmt.clock(max(r.end.timeIntervalSince(ctx.date), 0)))
                        .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                    if r.bonus > 0 { Text("上一组没做满，多歇 30 秒").font(.caption).foregroundStyle(.secondary) }
                    Text(workout.nextText).font(.callout).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
            HStack {
                Button("−15 秒") { workout.adjustRest(-15) }.buttonStyle(.bordered)
                Spacer()
                Button("跳过") { workout.skipRest() }.buttonStyle(.bordered)
                Spacer()
                Button("+15 秒") { workout.adjustRest(15) }.buttonStyle(.bordered)
            }
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        }
    }

    private func currentSection(_ item: WorkoutModel.Item) -> some View {
        let n = workout.setsDone(item).count
        return Section {
            if item.weight != nil || !item.timed {
                HStack {
                    Text("重量")
                    Spacer()
                    if let w = item.weight {
                        Button { workout.setWeight(max(w - item.step, 0)) } label: { Image(systemName: "minus.circle") }
                            .accessibilityLabel("减 \(WorkoutFmt.num(item.step))")
                        Text("\(WorkoutFmt.num(w)) \(item.unit)").monospacedDigit().frame(minWidth: 80)
                        Button { workout.setWeight(w + item.step) } label: { Image(systemName: "plus.circle") }
                            .accessibilityLabel("加 \(WorkoutFmt.num(item.step))")
                    } else {
                        Button("填重量") { workout.setWeight(item.unit == "lb" ? 45 : 20) }
                    }
                }
                .buttonStyle(.borderless)
                .font(.title3)
            }
            Stepper(value: $reps, in: 0...200, step: item.timed ? 5 : 1) {
                HStack {
                    Text(item.timed ? "秒" : "次数")
                    Spacer()
                    Text(WorkoutFmt.num(reps)).monospacedDigit().font(.title3)
                }
            }
            Button {
                workout.completeSet(reps: reps)
                reps = workout.currentItem?.reps ?? reps
            } label: {
                Label("做完这组", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        } header: {
            HStack {
                Text(item.name).font(.headline)
                Spacer()
                Text(n >= item.sets ? "加一组：第 \(n + 1) 组" : "第 \(n + 1) / \(item.sets) 组")
            }
        }
    }

    private var finishSheet: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("做了", value: "\(workout.done.count) 组")
                    if let s = workout.start {
                        LabeledContent("用时", value: "\(Int(Date().timeIntervalSince(s) / 60)) 分钟")
                    }
                }
                Section("备注（可以不写）") {
                    TextField("比如：卧推最后一组有点吃力", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Button(workout.done.isEmpty ? "结束（没有做的组，不记）" : "存下训练记录") {
                        if workout.finish(model: model, note: note) {
                            finishing = false
                            dismiss()
                        }
                    }
                    Button("不记，直接结束", role: .destructive) { confirmDiscard = true }
                } footer: {
                    Text("存在 健康/训练记录/ 里，电脑上能看到；动作页的记录表由 agent 之后补上。")
                }
            }
            .navigationTitle("练完了")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("接着练") { finishing = false } } }
            .confirmationDialog("这次训练不记了？", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("不记", role: .destructive) {
                    workout.discard()
                    finishing = false
                    dismiss()
                }
            }
        }
    }
}

/// 一个动作：目标 + 做过的组（95×9 · 95×9）
struct WorkoutRow: View {
    let item: WorkoutModel.Item
    let sets: [LoggedSet]
    let isCurrent: Bool

    static func target(_ item: WorkoutModel.Item) -> String {
        let goal = "\(item.sets)×\(WorkoutFmt.num(item.reps))\(item.timed ? " 秒" : "")"
        return item.weight.map { "\(goal) · \(WorkoutFmt.num($0)) \(item.unit)" } ?? goal
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: sets.count >= item.sets ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                .foregroundStyle(sets.count >= item.sets ? Theme.green : Color.accentColor)
                .accessibilityLabel(sets.count >= item.sets ? "做完了" : (isCurrent ? "正在做" : "还没做"))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.name).fontWeight(isCurrent ? .semibold : .regular)
                    Spacer()
                    Text(Self.target(item)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if !sets.isEmpty {
                    Text(sets.map { s in (s.weight.map { WorkoutFmt.num($0) + "×" } ?? "") + WorkoutFmt.num(s.reps) }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .contentShape(Rectangle())
    }
}
