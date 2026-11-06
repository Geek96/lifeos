import SwiftUI
import CoreMotion
import AudioToolbox
import LifeOSCore

/// 收藏（手机只看）：积分、陈列馆（按小套装排，没拿到的是空槽）；点一张拿起来看，倾斜手机光跟着走，点一下翻面。
/// 抽卡在电脑上，抽到的会同步过来。
struct PhoneCardsView: View {
    @Environment(PhoneModel.self) private var model
    @AppStorage("cardsPool") private var poolID = ""
    @State private var detail: PhoneCardRef?

    var body: some View {
        let cards = model.cards
        let pool = cards.pool(poolID) ?? cards.pools.first
        List {
            Section {
                LabeledContent("积分", value: "\(cards.balance)")
                LabeledContent("周日免费抽", value: "\(cards.freeDraws(now: model.clock, calendar: model.calendar)) 次")
            } footer: {
                Text("抽卡在电脑上（LifeOS → 收藏）；抽到的卡会同步到这里。")
            }
            if cards.pools.count > 1 {
                Picker("卡池", selection: $poolID) {
                    ForEach(cards.pools) { Text("\($0.name) \(cards.ownedCount($0))/\($0.cards.count)").tag($0.id) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if let pool {
                ForEach(pool.sets, id: \.self) { set in
                    let list = pool.cards(in: set)
                    let have = cards.ownedCount(pool, set: set)
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                            ForEach(list) { card in
                                if cards.count(pool, card) > 0 {
                                    CardFace(pool: pool, card: card, width: 104)
                                        .onTapGesture { detail = PhoneCardRef(pool: pool, card: card) }
                                        .accessibilityAddTraits(.isButton)
                                } else {
                                    CardSlot(pool: pool, card: card, width: 104)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    } header: {
                        HStack {
                            Text(set)
                            Spacer()
                            if have == list.count { Label("集齐了", systemImage: "seal.fill").foregroundStyle(Theme.orange) }
                            Text("\(have) / \(list.count)").monospacedDigit()
                        }
                    }
                }
                Section { Text(pool.credit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("收藏")
        .refreshable { model.reload() }
        .fullScreenCover(item: $detail) { PhoneCardDetail(ref: $0) }
        .onAppear { if cards.pool(poolID) == nil { poolID = cards.pools.first?.id ?? "" } }
    }
}

struct PhoneCardRef: Identifiable {
    var id: String { "\(pool.id)/\(card.id)" }
    let pool: CardPool
    let card: CollectibleCard
}

/// 拿起来看一张：倾斜手机卡跟着转、光跟着走；点一下翻面（有声音和震动，越稀有越重）
private struct PhoneCardDetail: View {
    @Environment(PhoneModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ref: PhoneCardRef
    @State private var flipped = false
    @State private var motion = TiltMotion()

    var body: some View {
        let n = model.cards.count(ref.pool, ref.card)
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 24) {
                FlippableCard(pool: ref.pool, card: ref.card, width: 300, flipped: $flipped, tilt: motion.tilt)
                Text("\(ref.card.rarity.label) · \(ref.card.rarity.frame)\(n > 1 ? " · 一共 \(n) 张" : "")")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                Button("关闭") { dismiss() }.buttonStyle(.bordered).tint(.white)
            }
        }
        .onChange(of: flipped) { feedback() }
        .onAppear { motion.start(); feedback() }
        .onDisappear { motion.stop() }
    }

    private func feedback() {
        AudioServicesPlaySystemSound(1104)
        switch ref.card.rarity {
        case .common: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .rare: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .epic: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .legend: UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// 手机倾斜 → -1…1（以拿起来那一刻的姿势为中心）
@Observable
@MainActor
private final class TiltMotion {
    var tilt: CGSize = .zero
    private let manager = CMMotionManager()
    private var base: CMAttitude?

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            MainActor.assumeIsolated {
                let a = m.attitude.copy() as! CMAttitude
                if self.base == nil { self.base = a.copy() as? CMAttitude }
                if let b = self.base { a.multiply(byInverseOf: b) }
                self.tilt = CGSize(width: max(-1, min(1, a.roll / 0.5)), height: max(-1, min(1, -a.pitch / 0.5)))
            }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
