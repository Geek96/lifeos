import SwiftUI
import AppKit
import Charts
import LifeOSCore

// 时间管理页的“专注”分页：日（那天每一段、按做什么分）/ 周、月（一共多少、每天多少、月历热力格、按做什么分、每一段）。
// 专注记录只有手机写（`健康/专注/`），这里只读。只陈述，不打分、不评价。

/// 专注 · 日
struct FocusDayPage: View {
    @Environment(AppModel.self) private var model
    let day: Date

    var body: some View {
        let cal = model.calendar
        let sessions = model.focus.filter { cal.isDate($0.start, inSameDayAs: day) }
        let week = HealthPeriod(scale: .week, anchor: day).interval(calendar: cal)
        let weekDays = Set(model.focus.filter { week.containsHalfOpen($0.start) }.map { cal.startOfDay(for: $0.start) })
        let weekTotal = model.focus.filter { week.containsHalfOpen($0.start) }.reduce(0) { $0 + $1.minutes }
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if sessions.isEmpty {
                Text("这天没有专注记录。专注在手机 LifeOS 的“专注”页开始，结束后点“记下”就会出现在这里。")
                    .foregroundStyle(.secondary)
            } else {
                StatRow {
                    StatTile(title: "专注了", value: FocusFormat.duration(sessions.reduce(0) { $0 + $1.minutes }))
                    StatTile(title: "几段", value: "\(sessions.count) 段")
                    StatTile(title: "最长一段", value: FocusFormat.duration(sessions.map(\.minutes).max() ?? 0))
                    StatTile(title: "这周有记录的天平均", value: weekDays.isEmpty ? "—" : FocusFormat.duration(weekTotal / Double(weekDays.count)))
                }
                FocusTimeline(day: day, sessions: sessions)
                FocusByLabel(sessions: sessions)
                FocusSessionTable(sessions: sessions, showDate: false, onSelectDay: nil)
            }
        }
    }
}

/// 专注 · 周 / 月
struct FocusRangePage: View {
    @Environment(AppModel.self) private var model
    let period: HealthPeriod
    let onSelectDay: (Date) -> Void

    var body: some View {
        let cal = model.calendar
        let iv = period.interval(calendar: cal)
        let days = period.days(calendar: cal)
        let sessions = model.focus.filter { iv.containsHalfOpen($0.start) }
        let total = sessions.reduce(0) { $0 + $1.minutes }
        let counted = Set(sessions.map { cal.startOfDay(for: $0.start) })
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            StatRow {
                StatTile(title: "一共专注", value: FocusFormat.duration(total))
                StatTile(title: "有记录的天平均", value: counted.isEmpty ? "—" : FocusFormat.duration(total / Double(counted.count)))
                StatTile(title: "记了", value: "\(counted.count) / \(days.count) 天")
                StatTile(title: "一共", value: "\(sessions.count) 段")
            }

            if period.scale == .month {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    SectionTitle(text: "每天专注多久", systemImage: "square.grid.3x3")
                    MonthHeatGrid(days: days, color: Theme.teal, cell: heat, onSelect: onSelectDay)
                    Text("颜色越深专注得越久（按 4 小时算满）；灰 = 没记。点一天看那天。").font(.caption).foregroundStyle(.secondary)
                }
            }

            DailyBarChart(title: "每天专注多久（小时）", points: days.map { d in
                .init(day: d, value: FocusSummary.minutes(on: d, in: model.focus, calendar: cal) / 60)
            }, color: Theme.teal, axisLabel: { $0 == $0.rounded() ? "\(Int($0)) h" : String(format: "%.1f h", $0) })

            if sessions.isEmpty {
                Text("这段时间没有专注记录。专注在手机 LifeOS 的“专注”页开始，结束后点“记下”就会出现在这里。")
                    .foregroundStyle(.secondary)
            } else {
                FocusByLabel(sessions: sessions)
                FocusSessionTable(sessions: sessions, showDate: true, onSelectDay: onSelectDay)
            }
        }
    }

    private func heat(_ d: Date) -> HeatCell {
        let m = FocusSummary.minutes(on: d, in: model.focus, calendar: model.calendar)
        guard m > 0 else { return HeatCell() }
        return HeatCell(fraction: min(m / 240, 1), text: String(format: "%.1fh", m / 60))
    }
}

/// 一天里每一段落在几点：横轴是时间，一段一根横条
private struct FocusTimeline: View {
    let day: Date
    let sessions: [FocusSession]

    var body: some View {
        let cal = Calendar.current
        let first = sessions.map(\.start).min() ?? day
        let last = sessions.map(\.end).max() ?? day
        // 默认看 8:00–22:00，有更早更晚的段就放宽到整点
        let lo = min(cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day, cal.dateInterval(of: .hour, for: first)?.start ?? first)
        let hi = max(cal.date(bySettingHour: 22, minute: 0, second: 0, of: day) ?? day, cal.dateInterval(of: .hour, for: last)?.end ?? last)
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "几点专注的", systemImage: "clock")
            Chart(sessions) { s in
                BarMark(xStart: .value("开始", s.start), xEnd: .value("结束", s.end), y: .value("", "专注"))
                    .foregroundStyle(Theme.teal.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .chartXScale(domain: lo...hi)
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 2)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis(.hidden)
            .frame(height: 50)
        }
    }
}

/// 按“做什么”分：多的在前
private struct FocusByLabel: View {
    let sessions: [FocusSession]

    var body: some View {
        let groups = Dictionary(grouping: sessions) { $0.label.isEmpty ? "没写做什么" : $0.label }
            .map { (label: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
            .sorted { $0.minutes > $1.minutes }
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: "按做什么分", systemImage: "chart.bar.xaxis")
            Chart(groups.prefix(10), id: \.label) { g in
                BarMark(x: .value("分钟", g.minutes), y: .value("做什么", g.label))
                    .foregroundStyle(Theme.teal.gradient)
                    .annotation(position: .trailing, spacing: 4) {
                        Text(FocusFormat.duration(g.minutes)).font(.caption).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(min(groups.count, 10)) * 28 + 8)
            if groups.count > 10 {
                Text("只列了最多的 10 项。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 每一段：时间、多久、做什么、离开、备注
private struct FocusSessionTable: View {
    let sessions: [FocusSession]
    let showDate: Bool
    let onSelectDay: ((Date) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "每一段", systemImage: "list.bullet")
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    Text("时间"); Text("分钟"); Text("做什么"); Text("离开"); Text("备注")
                }
                .font(.caption).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(sessions.reversed()) { s in
                    GridRow {
                        Text((showDate ? Fmt.string(s.start, "M月d日 EEE ") : "") + "\(Fmt.string(s.start, "H:mm"))–\(Fmt.string(s.end, "H:mm"))")
                            .foregroundStyle(.secondary)
                        Text("\(Int(s.minutes.rounded()))")
                        Text(s.label.isEmpty ? "—" : s.label)
                        Text(s.leaves > 0 ? "\(s.leaves) 次 · \(Int(s.leaveMinutes.rounded())) 分" : "—")
                        Text(s.note.isEmpty ? "—" : s.note).lineLimit(2)
                    }
                    .monospacedDigit()
                    .contentShape(Rectangle())
                    .onTapGesture { onSelectDay?(s.start) }
                }
            }
            .font(.callout)
            Text("“离开”= 专注时切到别的 App 超过 15 秒，锁屏不算。").font(.caption).foregroundStyle(.secondary)
        }
    }
}

enum FocusFormat {
    /// 95 → “1 小时 35 分”
    static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
        if m < 60 { return "\(m) 分钟" }
        return m % 60 == 0 ? "\(m / 60) 小时" : "\(m / 60) 小时 \(m % 60) 分"
    }
}

#if DEBUG
/// 调试：`-debugSnapshot 目录` 启动后把专注的 日 / 周 / 月 离屏画成 PNG 存进那个目录，然后退出（没有截屏权限时用来看样子）
enum FocusSnapshot {
    @MainActor
    static func runIfAsked(_ model: AppModel) async {
        guard let dir = UserDefaults.standard.string(forKey: "debugSnapshot") else { return }
        try? await Task.sleep(for: .seconds(2))
        let pages: [(String, AnyView)] = [
            ("focus_day", AnyView(FocusDayPage(day: Date()))),
            ("focus_week", AnyView(FocusRangePage(period: HealthPeriod(scale: .week, anchor: Date()), onSelectDay: { _ in }))),
            ("focus_month", AnyView(FocusRangePage(period: HealthPeriod(scale: .month, anchor: Date()), onSelectDay: { _ in }))),
        ]
        var pages2 = pages
        if let pool = model.cards.pools.first {
            let picks = CardRarity.allCases.compactMap { r in pool.cards.first { $0.rarity == r } }
            pages2.append(("cards_faces", AnyView(VStack(spacing: 20) {
                HStack(spacing: 16) { ForEach(picks) { CardFace(pool: pool, card: $0, width: 220) } }
                HStack(spacing: 16) { ForEach(picks) { CardFace(pool: pool, card: $0, width: 220, back: true) } }
                if let p2 = model.cards.pools.dropFirst().first {
                    HStack(spacing: 16) {
                        ForEach(CardRarity.allCases.compactMap { r in p2.cards.first { $0.rarity == r } }) { CardFace(pool: p2, card: $0, width: 220) }
                    }
                }
                HStack(spacing: 16) { CardBack(width: 220, glow: .legend); CardSlot(pool: pool, card: pool.cards[0], width: 220) }
            }.padding(30).background(Color(white: 0.12)))))
            pages2.append(("cards_page", AnyView(CardsView().frame(width: 900, height: 2400))))
        }
        // 讲稿页有 List 和 ScrollView，ImageRenderer 画不出来，放进离屏窗口里画
        let host = NSHostingView(rootView: PodcastNotesView().environment(model).frame(width: 1100, height: 760))
        let win = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 1100, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.orderFrontRegardless()
        try? await Task.sleep(for: .seconds(2))
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("podcast_notes.png"))
        }
        win.orderOut(nil)
        for (name, view) in pages2 {
            let r = ImageRenderer(content: view.environment(model).padding(24).frame(width: 760).background(Color.white))
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            }
        }
        NSApp.terminate(nil)
    }
}
#endif
