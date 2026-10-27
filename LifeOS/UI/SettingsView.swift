import SwiftUI
import AppKit
import LifeOSCore

/// 设置窗口（⌘,）：文件夹、CourseOS 联动、显示。改动写进 vault 的 lifeos.json。
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppearanceChoice.key) private var appearance = AppearanceChoice.system.rawValue
    @State private var draft = LifeConfig()

    var body: some View {
        TabView {
            Form {
                Section("LifeOS 文件夹") {
                    LabeledContent("位置") {
                        Text(model.vaultRoot?.path ?? "未选择").lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("选择…") { model.chooseVault() }
                        if let root = model.vaultRoot { Button("在访达中显示") { model.reveal(root) } }
                    }
                }
                Section("外观") {
                    Picker("外观", selection: $appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Stepper("时间格从 \(draft.dayHours.start):00 开始显示", value: $draft.dayHours.start, in: 0...12)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section {
                    LabeledContent("学期目录") {
                        Text(draft.courseos.semester.isEmpty ? "未连接" : draft.courseos.semester)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("选择…", action: chooseSemester)
                        if !draft.courseos.semester.isEmpty {
                            Button("断开") { draft.courseos.semester = "" }
                        }
                    }
                } header: {
                    Text("CourseOS 学期目录")
                } footer: {
                    Text("含 courseos.json 的那一层。LifeOS 只读它，不会写任何东西。")
                }
                Section("上课时间块") {
                    DatePicker("从", selection: dateBinding(\.classesFrom), displayedComponents: .date)
                    DatePicker("到", selection: dateBinding(\.classesUntil), displayedComponents: .date)
                }
                let multi = model.snapshot.courses.filter { ClassSchedule.parse($0.schedule).contains { !$0.sections.isEmpty } }
                if !multi.isEmpty {
                    Section {
                        ForEach(multi, id: \.id) { c in
                            let options = Array(Set(ClassSchedule.parse(c.schedule).flatMap(\.sections))).sorted()
                            Picker(c.id, selection: Binding(
                                get: { draft.courseos.sections[c.id] ?? "" },
                                set: { draft.courseos.sections[c.id] = $0.isEmpty ? nil : $0 })) {
                                Text("全部显示").tag("")
                                ForEach(options, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    } header: {
                        Text("我的 section")
                    } footer: {
                        Text("课程档案里写了多个时段的课，只显示你那一节。")
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("CourseOS", systemImage: "graduationcap") }

            Form {
                Section {
                    Toggle(isOn: $draft.plugins.health) {
                        Label("健康", systemImage: "heart")
                    }
                    Toggle(isOn: $draft.plugins.things) {
                        Label("物品", systemImage: "shippingbox")
                    }
                    Toggle(isOn: $draft.plugins.finance) {
                        Label("消费", systemImage: "creditcard")
                    }
                    Toggle(isOn: $draft.plugins.travel) {
                        Label("出行", systemImage: "airplane")
                    }
                    Toggle(isOn: $draft.plugins.vision) {
                        Label("远景", systemImage: "mountain.2")
                    }
                } header: {
                    Text("插件")
                } footer: {
                    Text("健康：今天练什么、饮食记录与每日目标对比（圆环）、复测、训练记录，数据在 健康/。物品：找东西、资产、补货与保养、售后、搬家，数据在 物品/，退货截止和保修到期会上日历。消费：流水、账户余额、订阅、预算，数据在 财务/，订阅扣款日会上日历。出行：近期、全部、想去，每次出行有按天规划的详情页，数据在 出行/。远景：愿景（时间甬道或清单）、项目（步骤与进度，带日期的步骤上日历）、奇思妙想，数据在 远景/。都由 agent 维护。")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("插件", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 520, height: 440)
        .onAppear { draft = model.config }
        .onChange(of: draft) { _, new in
            if new != model.config { model.saveConfig(new) }
        }
    }

    private func dateBinding(_ key: WritableKeyPath<LifeConfig.CourseOSLink, String?>) -> Binding<Date> {
        Binding(
            get: { draft.courseos[keyPath: key].flatMap { DateText.parse($0, calendar: model.calendar) } ?? Date() },
            set: { draft.courseos[keyPath: key] = DateText.format($0, withTime: false, calendar: model.calendar) })
    }

    private func chooseSemester() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "选择"
        panel.message = "选择 CourseOS 的学期目录（含 courseos.json）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent("courseos.json").path) else {
            model.feedback.show("这个文件夹里没有 courseos.json，不是 CourseOS 学期目录")
            return
        }
        draft.courseos.semester = url.path
    }
}
