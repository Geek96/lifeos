import SwiftUI
import LifeOSCore

/// 周视图：顶部每天的负荷 + 全天条（期限、时间窗、无时刻的课程截止），下面是 24 小时时间格。
/// 双击空白处新建约定；拖动自己的约定改时间（15 分钟对齐，可跨天）。
struct WeekView: View {
    @Environment(AppModel.self) private var model
    @State private var dragOffsets: [String: CGSize] = [:]

    static let hourHeight: CGFloat = 46
    static let gutter: CGFloat = 52

    var body: some View {
        let cal = model.calendar
        let week = model.weekRange
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
        let all = model.occurrences(in: week)
        let loads = model.loads(for: week)

        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.string(week.start, "yyyy年M月")).font(.title2.bold())
                Text("第 \(cal.component(.weekOfYear, from: week.start)) 周").foregroundStyle(.secondary)
                Spacer()
                Legend()
            }
            .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.m)

            DayHeaderRow(days: days, loads: loads)
            AllDayRow(days: days, occurrences: all.filter(isAllDayRow))
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        // 滚动锚点：每小时一个
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { h in Color.clear.frame(height: Self.hourHeight).id(h) }
                        }
                        .allowsHitTesting(false)
                        GeometryReader { geo in
                            let colWidth = (geo.size.width - Self.gutter) / 7
                            ZStack(alignment: .topLeading) {
                                HourGrid(colWidth: colWidth)
                                    .contentShape(Rectangle())
                                    .onTapGesture(count: 2) { p in createAt(p, days: days, colWidth: colWidth) }
                                    .onTapGesture { model.selected = nil }
                                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                                    let x = Self.gutter + CGFloat(index) * colWidth
                                    let dayItems = all.filter { cal.isDate($0.start, inSameDayAs: day) }
                                    ForEach(layout(dayItems.filter { $0.timedBlock != nil })) { slot in
                                        block(slot, x: x, colWidth: colWidth, day: day)
                                    }
                                    ForEach(dayItems.filter(isTimedMarker)) { o in
                                        marker(o, x: x, colWidth: colWidth, day: day)
                                    }
                                    if cal.isDate(day, inSameDayAs: model.clock) {
                                        NowLine(width: colWidth)
                                            .offset(x: x, y: y(for: model.clock, day: day) - 4)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: Self.hourHeight * 24)
                }
                .task {
                    // 等布局完成再滚到早上
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(max(0, model.config.dayHours.start), anchor: .top)
                }
            }
        }
    }

    private func isAllDayRow(_ o: Occurrence) -> Bool {
        o.allDay || o.style == .window
    }

    private func isTimedMarker(_ o: Occurrence) -> Bool {
        !o.allDay && o.timedBlock == nil && o.style != .window
    }

    // MARK: - 坐标

    private func y(for date: Date, day: Date) -> CGFloat {
        let minutes = date.timeIntervalSince(model.calendar.startOfDay(for: day)) / 60
        return CGFloat(min(max(minutes, 0), 24 * 60)) / 60 * Self.hourHeight
    }

    private func createAt(_ p: CGPoint, days: [Date], colWidth: CGFloat) {
        guard p.x > Self.gutter else { return }
        let index = min(6, max(0, Int((p.x - Self.gutter) / colWidth)))
        let minutes = Int(p.y / Self.hourHeight * 60) / 30 * 30
        guard let start = model.calendar.date(byAdding: .minute, value: minutes, to: days[index]) else { return }
        model.newItem(kind: .event, at: start)
    }

    // MARK: - 时间块

    struct Slot: Identifiable {
        var occurrence: Occurrence
        var column: Int
        var columns: Int
        var id: String { occurrence.id }
    }

    /// 重叠的块并排：贪心分列，同一簇共享列数
    private func layout(_ items: [Occurrence]) -> [Slot] {
        let sorted = items.sorted { ($0.timedBlock!.start, $0.timedBlock!.end) < ($1.timedBlock!.start, $1.timedBlock!.end) }
        var result: [Slot] = []
        var cluster: [Slot] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast
        func flush() {
            let n = max(columnEnds.count, 1)
            result += cluster.map { Slot(occurrence: $0.occurrence, column: $0.column, columns: n) }
            cluster = []
            columnEnds = []
        }
        for o in sorted {
            let b = o.timedBlock!
            if b.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= b.start }) {
                columnEnds[free] = b.end
                cluster.append(Slot(occurrence: o, column: free, columns: 0))
            } else {
                columnEnds.append(b.end)
                cluster.append(Slot(occurrence: o, column: columnEnds.count - 1, columns: 0))
            }
            clusterEnd = max(clusterEnd, b.end)
        }
        flush()
        return result
    }

    @ViewBuilder
    private func block(_ slot: Slot, x: CGFloat, colWidth: CGFloat, day: Date) -> some View {
        let o = slot.occurrence
        let b = o.timedBlock!
        let top = y(for: b.start, day: day)
        let height = max(y(for: b.end, day: day) - top, 20)
        let w = (colWidth - 4) / CGFloat(slot.columns)
        let draggable = o.style == .event && o.itemID != nil
        let offset = dragOffsets[o.id] ?? .zero
        let tint = Theme.tint(o.style)
        let isSelected = model.selected?.id == o.id

        VStack(alignment: .leading, spacing: 1) {
            Text(o.title).font(.caption.weight(.semibold)).lineLimit(height > 34 ? 2 : 1)
            if height > 34 {
                Text(o.style == .classSession ? o.subtitle : "\(Fmt.time(b.start))–\(Fmt.time(b.end))")
                    .font(.caption2).lineLimit(1).opacity(0.8)
            }
        }
        .padding(.horizontal, 5).padding(.vertical, 3)
        .frame(width: w - 2, height: height, alignment: .topLeading)
        .foregroundStyle(o.style == .classSession ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
        .background(tint.opacity(o.style == .classSession ? 0.10 : 0.16), in: RoundedRectangle(cornerRadius: 5))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3).clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isSelected ? tint : .clear, lineWidth: 1.5))
        .opacity(o.isPast(now: model.clock) && dragOffsets[o.id] == nil ? 0.45 : 1)
        .offset(x: x + 2 + CGFloat(slot.column) * w + offset.width, y: top + offset.height)
        .zIndex(dragOffsets[o.id] != nil ? 10 : 1)
        .onTapGesture(count: 2) { if let item = model.item(for: o) { model.edit(item) } }
        .onTapGesture { model.selected = o; model.showInspector = true }
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { v in dragOffsets[o.id] = snapped(v.translation, colWidth: colWidth) }
            .onEnded { v in
                let s = snapped(v.translation, colWidth: colWidth)
                dragOffsets[o.id] = nil
                let days = Int((s.width / colWidth).rounded())
                let minutes = Int((s.height / Self.hourHeight * 60).rounded())
                if let moved = model.calendar.date(byAdding: .day, value: days, to: o.start)?
                    .addingTimeInterval(TimeInterval(minutes * 60)) {
                    model.move(o, to: moved)
                }
            }, isEnabled: draggable)
        .help(draggable ? "\(o.title)（拖动改时间，双击编辑）" : o.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(o.style.label)：\(o.title)，\(Fmt.time(b.start)) 到 \(Fmt.time(b.end))")
    }

    /// 拖动对齐：横向按整天，纵向按 15 分钟
    private func snapped(_ t: CGSize, colWidth: CGFloat) -> CGSize {
        let quarter = Self.hourHeight / 4
        return CGSize(width: (t.width / colWidth).rounded() * colWidth, height: (t.height / quarter).rounded() * quarter)
    }

    /// 有时刻的截止：细线 + 小标签
    private func marker(_ o: Occurrence, x: CGFloat, colWidth: CGFloat, day: Date) -> some View {
        let tint = Theme.tint(o.style)
        return HStack(spacing: 3) {
            Image(systemName: Theme.icon(o.style)).font(.system(size: 9, weight: .bold))
            Text("\(Fmt.time(o.start)) \(o.title)").font(.caption2.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 4).padding(.vertical, 1)
        .frame(width: colWidth - 6, alignment: .leading)
        .foregroundStyle(tint)
        .background(.background, in: Capsule())
        .background(tint.opacity(0.18), in: Capsule())
        .overlay(alignment: .top) { Rectangle().fill(tint).frame(height: 1.5).offset(y: -1) }
        .opacity(o.isPast(now: model.clock) || o.done ? 0.45 : 1)
        .offset(x: x + 3, y: y(for: o.start, day: day) - 1)
        .zIndex(5)
        .onTapGesture { model.selected = o; model.showInspector = true }
        .help(o.title)
        .accessibilityLabel("\(o.style.label)：\(o.title)，\(Fmt.time(o.start))")
    }
}

/// 每天的表头：星期、日期（今天高亮）、负荷
struct DayHeaderRow: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let loads: [Date: DayLoad]

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: WeekView.gutter, height: 1)
            ForEach(days, id: \.self) { day in
                let today = model.calendar.isDate(day, inSameDayAs: model.clock)
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(Fmt.string(day, "EEE")).foregroundStyle(.secondary)
                        Text(Fmt.string(day, "d"))
                            .fontWeight(today ? .bold : .regular)
                            .foregroundStyle(today ? Color.white : Color.primary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(today ? Theme.red : .clear, in: Capsule())
                    }
                    LoadBadge(load: loads[model.calendar.startOfDay(for: day)])
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.anchor = day; model.page = .today }
                .help("双击查看这一天")
            }
        }
        .padding(.bottom, 6)
    }
}

/// 全天条：期限、时间窗、全天约定、不带时刻的课程截止和考试
struct AllDayRow: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let occurrences: [Occurrence]
    @State private var expanded = false

    var body: some View {
        let limit = expanded ? 20 : 3
        HStack(alignment: .top, spacing: 0) {
            Text("全天").font(.caption2).foregroundStyle(.secondary)
                .frame(width: WeekView.gutter - 6, alignment: .trailing).padding(.trailing, 6).padding(.top, 3)
            ForEach(days, id: \.self) { day in
                let list = occurrences.filter { $0.touches(day: day, calendar: model.calendar) }
                    .sorted { ($0.style == .window ? 1 : 0, $0.title) < ($1.style == .window ? 1 : 0, $1.title) }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(list.prefix(limit)) { o in
                        Chip(occurrence: o)
                    }
                    if list.count > limit {
                        Button("还有 \(list.count - limit) 项") { expanded = true }
                            .buttonStyle(.link).font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 28)
    }
}

/// 小条目（全天行、月视图共用）
struct Chip: View {
    @Environment(AppModel.self) private var model
    let occurrence: Occurrence

    var body: some View {
        let o = occurrence
        let tint = Theme.tint(o.style)
        HStack(spacing: 3) {
            Image(systemName: Theme.icon(o.style)).font(.system(size: 9, weight: .semibold))
            Text(o.title).lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 4).padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(tint)
        .background(tint.opacity(o.style == .window ? 0.10 : 0.16), in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(model.selected?.id == o.id ? tint : .clear))
        .opacity(o.isPast(now: model.clock) || o.done ? 0.45 : 1)
        .strikethrough(o.done)
        .contentShape(Rectangle())
        .onTapGesture { model.selected = o; model.showInspector = true }
        .onTapGesture(count: 2) { if let item = model.item(for: o) { model.edit(item) } }
        .help("\(o.style.label)：\(o.title)")
        .accessibilityLabel("\(o.style.label)：\(o.title)")
    }
}

struct HourGrid: View {
    let colWidth: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { h in
                let y = CGFloat(h) * WeekView.hourHeight
                Text(h == 0 ? "" : "\(h):00")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: WeekView.gutter - 8, alignment: .trailing)
                    .offset(y: y - 7)
                Rectangle().fill(.separator.opacity(0.6)).frame(height: 0.5)
                    .offset(x: WeekView.gutter, y: y)
            }
            ForEach(0..<8, id: \.self) { i in
                Rectangle().fill(.separator.opacity(0.45)).frame(width: 1, height: WeekView.hourHeight * 24)
                    .offset(x: WeekView.gutter + CGFloat(i) * colWidth)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct NowLine: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.red).frame(width: 8, height: 8)
            Rectangle().fill(Theme.red).frame(width: width - 8, height: 1.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 图例：颜色 + 文字
struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach([Occurrence.Style.event, .deadline, .window, .classSession, .courseDue, .courseExam], id: \.self) { s in
                HStack(spacing: 4) {
                    Circle().fill(Theme.tint(s)).frame(width: 7, height: 7)
                    Text(s.label)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
