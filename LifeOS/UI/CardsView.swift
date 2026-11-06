import SwiftUI
import AppKit
import LifeOSCore

// 收藏页：积分（只加不减，怎么来的都列着）→ 抽卡（选卡池；单抽 / 十连 / 周日免费一抽）→ 陈列馆（按小套装排，没拿到的是空槽）。
// 抽卡只在电脑上；抽到的记进 收藏/抽卡记录.md，手机上也能看。

struct CardsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("cardsPool") private var poolID = ""
    @State private var session: DrawSession?
    @State private var detail: CardRef?
    @State private var showAllPoints = false

    var body: some View {
        let cards = model.cards
        let pool = cards.pool(poolID) ?? cards.pools.first
        HealthPageScaffold(title: "收藏") {
            if cards.pools.isEmpty {
                Text("还没有卡池。卡池放在 收藏/卡池/<名字>/卡池.json，图放在同一个文件夹的 图/ 里。").foregroundStyle(.secondary)
            } else {
                summary(cards)
                if !model.newPoints.isEmpty { newPointsNote }
                if let pool { drawBox(pool, cards) }
                pointsList(cards)
                if let pool { gallery(pool, cards) }
            }
        }
        .overlay {
            if let session {
                DrawStage(session: session) { self.session = nil }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session?.id)
        .sheet(item: $detail) { ref in CardDetail(ref: ref) }
        .onAppear { if cards.pool(poolID) == nil { poolID = cards.pools.first?.id ?? "" } }
    }

    // MARK: 积分

    private func summary(_ cards: CardsSnapshot) -> some View {
        var cal = model.calendar
        cal.firstWeekday = 2
        let week = cal.dateInterval(of: .weekOfYear, for: model.clock)
        let thisWeek = cards.ledger.filter { week?.contains($0.date) == true }.reduce(0) { $0 + $1.points }
        let total = cards.pools.reduce(0) { $0 + $1.cards.count }
        let owned = cards.pools.reduce(0) { $0 + cards.ownedCount($1) }
        return StatRow {
            StatTile(title: "积分", value: "\(cards.balance)")
            StatTile(title: "这周得了", value: "+\(thisWeek)")
            StatTile(title: "收集", value: "\(owned) / \(total)")
            StatTile(title: "周日免费抽", value: "\(cards.freeDraws(now: model.clock, calendar: model.calendar)) 次")
        }
    }

    private var newPointsNote: some View {
        HStack {
            Label("刚记上 \(model.newPoints.count) 件做到的事，+\(model.newPoints.reduce(0) { $0 + $1.points }) 积分", systemImage: "sparkles")
            Spacer()
            Button("知道了") { model.newPoints = [] }
        }
        .padding(Theme.Space.m)
        .background(Theme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func pointsList(_ cards: CardsSnapshot) -> some View {
        let rows = Array(cards.ledger.reversed().prefix(showAllPoints ? 500 : 8))
        return VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(text: "积分怎么来的", systemImage: "plus.circle")
            if rows.isEmpty {
                Text("还没有。记全一天饮食、练一次、专注满一小时、记一晚睡眠……都会自动加分。").foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                ForEach(rows) { e in
                    GridRow {
                        Text(Fmt.string(e.date, "M月d日")).foregroundStyle(.secondary).monospacedDigit()
                        Text(e.text).lineLimit(1)
                        Text("+\(e.points)").monospacedDigit().foregroundStyle(Theme.green).gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.callout)
            if cards.ledger.count > 8 {
                Button(showAllPoints ? "收起" : "全部 \(cards.ledger.count) 条") { showAllPoints.toggle() }
                    .buttonStyle(.link)
            }
            Text("只加不减：饮食记全 +2、蛋白质达标 +3、热量达到目标 +2；练一次 +5、破纪录 +3；专注每满 1 小时 +2（一天最多 6 小时）；记睡眠 +1、睡够 7 小时 +2；每周、每月过完还有额外奖励；想法变成项目、项目做完各 +1；出行 +5，过夜的 +20。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: 抽卡

    private func drawBox(_ pool: CardPool, _ cards: CardsSnapshot) -> some View {
        let free = cards.freeDraws(now: model.clock, calendar: model.calendar)
        return VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                SectionTitle(text: "抽卡", systemImage: "sparkles.rectangle.stack")
                Spacer()
                TabStrip(tabs: cards.pools.map { ($0.id, "\($0.name) \(cards.ownedCount($0))/\($0.cards.count)") }, selection: $poolID)
            }
            HStack(spacing: Theme.Space.m) {
                Button { draw(pool, count: 1) } label: {
                    Label("抽一张 · \(CardDrawer.singleCost) 积分", systemImage: "rectangle.portrait")
                }
                .disabled(cards.balance < CardDrawer.singleCost)
                Button { draw(pool, count: 10) } label: {
                    Label("十连 · \(CardDrawer.tenCost) 积分", systemImage: "rectangle.stack")
                }
                .disabled(cards.balance < CardDrawer.tenCost)
                if free > 0 {
                    Button { draw(pool, count: 1, free: true) } label: {
                        Label("免费抽一张（周日送的）", systemImage: "gift")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            Text("概率：普通 70%、稀有 22%、史诗 7%、传说 1%。十张里至少一张史诗以上；连着 9 张普通，下一张至少稀有。没集齐之前优先给新卡，重复的退积分（铜 5、银 10、金 20、镭射 50）。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(Theme.Space.l)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func draw(_ pool: CardPool, count: Int, free: Bool = false) {
        guard let draws = model.drawCards(pool: pool, count: count, free: free) else { return }
        session = DrawSession(pool: pool, draws: draws)
    }

    // MARK: 陈列馆

    private func gallery(_ pool: CardPool, _ cards: CardsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(text: "陈列馆 · \(pool.name)", systemImage: "building.columns")
                Spacer()
                Text("\(cards.ownedCount(pool)) / \(pool.cards.count)").foregroundStyle(.secondary).monospacedDigit()
            }
            ForEach(pool.sets, id: \.self) { set in
                let list = pool.cards(in: set)
                let have = cards.ownedCount(pool, set: set)
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    HStack(spacing: Theme.Space.s) {
                        Text(set).font(.headline)
                        Text("\(have) / \(list.count)").foregroundStyle(.secondary).monospacedDigit()
                        if have == list.count {
                            Label("集齐了", systemImage: "seal.fill").font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.orange)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: 14, alignment: .top)], spacing: 16) {
                        ForEach(list) { card in
                            let n = cards.count(pool, card)
                            if n > 0 {
                                CardFace(pool: pool, card: card, width: 140)
                                    .overlay(alignment: .topTrailing) {
                                        if n > 1 {
                                            Text("×\(n)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(.black.opacity(0.6), in: Capsule()).foregroundStyle(.white)
                                                .offset(x: 4, y: -4)
                                        }
                                    }
                                    .onTapGesture { detail = CardRef(pool: pool, card: card) }
                                    .accessibilityAddTraits(.isButton)
                            } else {
                                CardSlot(pool: pool, card: card, width: 140)
                            }
                        }
                    }
                }
            }
            Text(pool.credit).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DrawSession: Identifiable {
    let id = UUID()
    let pool: CardPool
    let draws: [CardDraw]
}

struct CardRef: Identifiable {
    var id: String { "\(pool.id)/\(card.id)" }
    let pool: CardPool
    let card: CollectibleCard
}

// MARK: - 抽卡动画

/// 卡包抖几下 → 按这次最稀有的那张爆出颜色光（金、镭射多一圈放射光）→ 卡背朝上摆好、发着各自稀有度的光，点一张翻一张
private struct DrawStage: View {
    let session: DrawSession
    let close: () -> Void
    @State private var phase = 0
    @State private var revealed: Set<Int> = []

    private var best: CardRarity { session.draws.map(\.rarity).max() ?? .common }

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.78)).ignoresSafeArea()
                .onTapGesture { if phase >= 2, revealed.count == session.draws.count { close() } }
            if phase >= 1 {
                Rays(color: CardStyle.glow(best), strong: best >= .epic)
            }
            if phase < 2 {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    CardBack(width: 220)
                        .rotationEffect(.degrees(phase == 0 ? sin(t * 38) * 4 : 0))
                        .scaleEffect(phase == 1 ? 1.25 : 1)
                        .opacity(phase == 1 ? 0 : 1)
                }
            } else {
                VStack(spacing: Theme.Space.xl) {
                    let width: CGFloat = session.draws.count > 1 ? 150 : 260
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 18), count: min(session.draws.count, 5)), spacing: 22) {
                        ForEach(Array(session.draws.enumerated()), id: \.offset) { i, d in
                            if let card = session.pool.card(d.card) {
                                RevealCard(pool: session.pool, card: card, draw: d, width: width, revealed: revealed.contains(i))
                                    .onTapGesture { reveal(i) }
                                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                    }
                    HStack(spacing: Theme.Space.m) {
                        if revealed.count < session.draws.count {
                            Button("全部翻开") {
                                for i in session.draws.indices { reveal(i, sound: false) }
                                Sounds.play(best)
                            }
                        }
                        Button("收下") { close() }.keyboardShortcut(.defaultAction)
                    }
                    .controlSize(.large)
                }
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.easeOut(duration: 0.25)) { phase = 1 }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { phase = 2 }
            if session.draws.count == 1 {
                try? await Task.sleep(for: .milliseconds(500))
                reveal(0)
            }
        }
    }

    private func reveal(_ i: Int, sound: Bool = true) {
        guard !revealed.contains(i) else { return }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { _ = revealed.insert(i) }
        if sound { Sounds.play(session.draws[i].rarity) }
    }
}

/// 背面朝上（按稀有度发光）→ 翻过来；下面一行写“新！”或“重复，退 N 积分”
private struct RevealCard: View, Animatable {
    let pool: CardPool
    let card: CollectibleCard
    let draw: CardDraw
    let width: CGFloat
    var angle: Double

    init(pool: CardPool, card: CollectibleCard, draw: CardDraw, width: CGFloat, revealed: Bool) {
        self.pool = pool
        self.card = card
        self.draw = draw
        self.width = width
        angle = revealed ? 180 : 0
    }

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if angle < 90 {
                    CardBack(width: width, glow: draw.rarity)
                } else {
                    CardFace(pool: pool, card: card, width: width)
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
            }
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(1 + 0.08 * sin(angle / 180 * .pi))
            Text(angle < 90 ? " " : (draw.isNew ? "新！\(draw.rarity.label)" : "重复 · 退 \(draw.refund) 积分"))
                .font(.callout.weight(draw.isNew ? .bold : .regular))
                .foregroundStyle(draw.isNew ? CardStyle.glow(draw.rarity) : .white.opacity(0.6))
        }
        .contentShape(Rectangle())
    }
}

/// 中间爆开的光：一圈放大的光晕；史诗、传说再加一圈慢慢转的光芒
private struct Rays: View {
    let color: Color
    let strong: Bool
    @State private var go = false

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color, color.opacity(0)], center: .center, startRadius: 0, endRadius: 260))
                .frame(width: 520, height: 520)
                .scaleEffect(go ? 1.5 : 0.2)
                .opacity(go ? 0 : 0.95)
            if strong {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    Canvas { c, size in
                        let center = CGPoint(x: size.width / 2, y: size.height / 2)
                        for i in 0..<20 {
                            let a = Double(i) / 20 * 2 * .pi + t * 0.25
                            var p = Path()
                            p.move(to: center)
                            p.addLine(to: CGPoint(x: center.x + cos(a - 0.04) * 520, y: center.y + sin(a - 0.04) * 520))
                            p.addLine(to: CGPoint(x: center.x + cos(a + 0.04) * 520, y: center.y + sin(a + 0.04) * 520))
                            c.fill(p, with: .radialGradient(Gradient(colors: [color.opacity(0.55), color.opacity(0)]),
                                                            center: center, startRadius: 40, endRadius: 520))
                        }
                    }
                }
                .frame(width: 1040, height: 1040)
                .opacity(go ? 0.8 : 0)
            }
        }
        .allowsHitTesting(false)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { go = true } }
    }
}

/// 翻开时的声音：越稀有越亮
@MainActor
private enum Sounds {
    static func play(_ r: CardRarity) {
        let name: String = switch r { case .common: "Pop"; case .rare: "Tink"; case .epic: "Glass"; case .legend: "Hero" }
        NSSound(named: name)?.play()
    }
}

// MARK: - 细看一张

/// 把一张卡拿起来看：鼠标移动卡跟着倾斜、光跟着走；点一下翻到背面；名画可以打开原图
private struct CardDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: CardRef
    @State private var flipped = false
    @State private var tilt: CGSize = .zero

    var body: some View {
        let draws = model.cards.draws.filter { $0.pool == ref.pool.id && $0.card == ref.card.id }
        VStack(spacing: Theme.Space.l) {
            FlippableCard(pool: ref.pool, card: ref.card, width: 340, flipped: $flipped, tilt: tilt)
                .padding(30)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p):
                        tilt = CGSize(width: (p.x / 400 - 0.5) * 2, height: (p.y / (340 * CardStyle.ratio + 60) - 0.5) * 2)
                    case .ended: tilt = .zero
                    }
                }
            HStack(spacing: Theme.Space.m) {
                Text("\(ref.card.rarity.label) · \(ref.card.rarity.frame)")
                if let first = draws.first {
                    Text("\(Fmt.string(first.time, "M月d日"))第一次抽到")
                }
                if draws.count > 1 { Text("一共 \(draws.count) 张") }
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(flipped ? "看正面" : "看背面") { flipped.toggle() }
                if ref.pool.style == .painting {
                    Button("看原图") { NSWorkspace.shared.open(ref.pool.imageURL(ref.card)) }
                }
                if let src = ref.card.source, let url = URL(string: src) {
                    Link("出处", destination: url)
                }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 460)
    }
}
