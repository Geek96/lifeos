import SwiftUI
import ImageIO
import LifeOSCore

// 收藏卡的样子（电脑、手机共用）：正面大图 + 中文名 + 英文名，系列和编号是小字；背面三行资料 + 小故事 + 冷知识。
// 稀有度看边框：铜（哑光）/ 银（一道光扫过）/ 金（光扫过 + 光晕）/ 镭射（彩虹边框流动 + 彩虹膜和星点）。
// 奇观图按卡的比例画好、铺满；名画整幅装在米白衬纸里，不裁。

enum CardStyle {
    static let ratio: CGFloat = 7.4 / 5
    static let paper = Color(red: 0.965, green: 0.94, blue: 0.886)
    static let paperInk = Color(red: 0.165, green: 0.149, blue: 0.129)
    static let matte = Color(red: 0.937, green: 0.91, blue: 0.847)

    static func frame(_ r: CardRarity) -> [Color] {
        func c(_ hex: UInt32) -> Color {
            Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        switch r {
        case .common: return [c(0x7A4A2A), c(0xC98A5A), c(0x8A5634), c(0xD9A070), c(0x6E4024)]
        case .rare: return [c(0x8D949C), c(0xEEF1F4), c(0x9AA1AA), c(0xFFFFFF), c(0x7D848C)]
        case .epic: return [c(0x8A6214), c(0xFFE08A), c(0xB8860B), c(0xFFF2B8), c(0x9A6D12)]
        case .legend: return [c(0xFF6EC7), c(0xFFD36E), c(0x8AFFC1), c(0x6EC8FF), c(0xB86EFF), c(0xFF6EC7)]
        }
    }

    /// 稀有度的“光”：抽卡时的光晕、未翻开时卡背的发光
    static func glow(_ r: CardRarity) -> Color {
        switch r {
        case .common: Color(red: 0.85, green: 0.63, blue: 0.44)
        case .rare: Color(red: 0.75, green: 0.85, blue: 1)
        case .epic: Color(red: 1, green: 0.82, blue: 0.35)
        case .legend: Color(red: 0.72, green: 0.43, blue: 1)
        }
    }
}

/// 卡图：按需要的大小缩小解码，缓存起来（陈列馆一次画几十张）
@MainActor
final class CardImages {
    static let shared = CardImages()
    private var cache: [String: CGImage] = [:]

    func image(_ url: URL, maxPixel: Int) -> CGImage? {
        let bucket = maxPixel <= 600 ? 600 : 1600
        let key = "\(url.path)#\(bucket)"
        if let hit = cache[key] { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: bucket,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        cache[key] = img
        return img
    }
}

/// 一张卡（正面或背面）。`tilt` 是 -1…1 的倾斜，用来挪动高光
struct CardFace: View {
    let pool: CardPool
    let card: CollectibleCard
    var width: CGFloat = 200
    var back = false
    var tilt: CGSize = .zero

    private var s: CGFloat { width / 250 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14 * s)
                .fill(LinearGradient(colors: CardStyle.frame(card.rarity), startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { if card.rarity == .legend { LegendBorder(cornerRadius: 14 * s) } }
            Group {
                if back { backSide } else { frontSide }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8 * s))
            .padding(9 * s)
            if !back {
                CardShine(rarity: card.rarity, tilt: tilt, cornerRadius: 8 * s)
                    .padding(9 * s)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: width * CardStyle.ratio)
        .shadow(color: card.rarity >= .epic ? CardStyle.glow(card.rarity).opacity(0.45) : .black.opacity(0.35),
                radius: card.rarity >= .epic ? 14 * s : 8 * s, y: 6 * s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.name)，\(card.rarity.label)卡")
    }

    private var frontSide: some View {
        VStack(spacing: 0) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(card.name).font(.system(size: 21 * s, weight: .bold, design: .serif)).tracking(1.2 * s)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(card.nameEn.uppercased()).font(.system(size: 10.5 * s, design: .serif)).tracking(1.3 * s)
                    .opacity(0.7).lineLimit(1).minimumScaleFactor(0.6)
                Text("\(pool.name) · \(card.set) · \(pool.number(card))")
                    .font(.system(size: 8.5 * s)).opacity(0.55).lineLimit(1).minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2 * s)
            }
            .foregroundStyle(CardStyle.paperInk)
            .padding(.horizontal, 12 * s).padding(.top, 8 * s).padding(.bottom, 6 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CardStyle.paper)
        }
    }

    @ViewBuilder private var picture: some View {
        let img = CardImages.shared.image(pool.imageURL(card), maxPixel: Int(width * 3))
        switch pool.style {
        case .poster:
            if let img {
                Image(decorative: img, scale: 1).resizable().scaledToFill()
            } else { Color.gray.opacity(0.3) }
        case .painting:
            ZStack {
                CardStyle.matte
                if let img {
                    Image(decorative: img, scale: 1).resizable().scaledToFit()
                        .overlay(Rectangle().stroke(.black.opacity(0.2), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.25), radius: 3 * s, y: 2 * s)
                        .padding(11 * s)
                }
            }
        }
    }

    private var backSide: some View {
        VStack(alignment: .leading, spacing: 7 * s) {
            VStack(alignment: .leading, spacing: 1 * s) {
                Text(card.name).font(.system(size: 21 * s, weight: .bold, design: .serif))
                Text(card.nameEn.uppercased()).font(.system(size: 10.5 * s, design: .serif)).tracking(1.3 * s).opacity(0.7)
            }
            Rectangle().fill(CardStyle.paperInk.opacity(0.2)).frame(height: 0.5)
            VStack(alignment: .leading, spacing: 2 * s) {
                ForEach(Array(card.facts.enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                        Text(f.first ?? "").opacity(0.55).frame(width: 30 * s, alignment: .leading)
                        Text(f.dropFirst().first ?? "").fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 11 * s))
            Text(card.story).font(.system(size: 11.3 * s)).lineSpacing(2.5 * s).fixedSize(horizontal: false, vertical: true)
            if !card.fun.isEmpty {
                Text("冷知识　\(card.fun)").font(.system(size: 10.5 * s)).lineSpacing(1.5 * s)
                    .foregroundStyle(Color(red: 0.42, green: 0.32, blue: 0.16))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(CardStyle.paperInk)
        .padding(13 * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CardStyle.paper)
    }
}

/// 卡背（还没翻开时）：深蓝底 + 金色细纹 + “陈列馆”，按稀有度发光
struct CardBack: View {
    var width: CGFloat = 200
    var glow: CardRarity? = nil

    var body: some View {
        let s = width / 250
        RoundedRectangle(cornerRadius: 14 * s)
            .fill(Color(red: 0.11, green: 0.14, blue: 0.25))
            .overlay {
                Canvas { ctx, size in
                    var p = Path()
                    let step: CGFloat = 14 * s
                    var x: CGFloat = -size.height
                    while x < size.width {
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                        x += step
                    }
                    ctx.stroke(p, with: .color(.white.opacity(0.05)), lineWidth: 6 * s)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14 * s))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10 * s).stroke(Color(red: 0.79, green: 0.66, blue: 0.42), lineWidth: 2.5 * s).padding(8 * s)
            }
            .overlay {
                VStack(spacing: 6 * s) {
                    Image(systemName: "sparkles").font(.system(size: 26 * s))
                    Text("陈列馆").font(.system(size: 20 * s, weight: .semibold, design: .serif)).tracking(6 * s)
                }
                .foregroundStyle(Color(red: 0.79, green: 0.66, blue: 0.42))
            }
            .frame(width: width, height: width * CardStyle.ratio)
            .shadow(color: glow.map { CardStyle.glow($0).opacity($0 == .common ? 0.35 : 0.9) } ?? .black.opacity(0.4),
                    radius: glow.map { $0 >= .epic ? 26 * s : 16 * s } ?? 8 * s)
            .accessibilityLabel(glow.map { "还没翻开的卡，发着\($0.frame)色的光" } ?? "卡背")
    }
}

/// 陈列馆里还没拿到的位置：暗色空槽 + 编号
struct CardSlot: View {
    let pool: CardPool
    let card: CollectibleCard
    var width: CGFloat = 200

    var body: some View {
        let s = width / 250
        RoundedRectangle(cornerRadius: 14 * s)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5 * s, dash: [6 * s, 5 * s]))
            .foregroundStyle(.secondary.opacity(0.5))
            .background(RoundedRectangle(cornerRadius: 14 * s).fill(.quaternary.opacity(0.4)))
            .overlay {
                VStack(spacing: 6 * s) {
                    Text("？").font(.system(size: 40 * s, weight: .light, design: .serif))
                    Text(pool.number(card)).font(.system(size: 12 * s).monospacedDigit())
                }
                .foregroundStyle(.secondary)
            }
            .frame(width: width, height: width * CardStyle.ratio)
            .accessibilityLabel("还没拿到，第 \(pool.number(card)) 张")
    }
}

/// 镭射卡的边框：彩虹慢慢转
private struct LegendBorder: View {
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(AngularGradient(colors: CardStyle.frame(.legend), center: .center, angle: .degrees(t * 60)))
        }
    }
}

/// 卡面上的光：银、金是一道慢慢扫过的白光；镭射是跟着倾斜移动的彩虹膜 + 闪烁星点
private struct CardShine: View {
    let rarity: CardRarity
    let tilt: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        switch rarity {
        case .common: Color.clear
        case .rare, .epic:
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.5) / 4.5
                // 前 60% 的时间扫过去，后面停一会儿
                let p = min(t / 0.6, 1)
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(rarity == .epic ? 0.45 : 0.35), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.5)
                        .rotationEffect(.degrees(15))
                        .offset(x: (p * 2.2 - 0.85) * g.size.width + tilt.width * 30)
                        .blendMode(.plusLighter)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        case .legend:
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let phase = sin(t / 3) * 0.5 + 0.5
                ZStack {
                    LinearGradient(colors: [.pink, .yellow, .green, .cyan, .purple, .pink, .yellow],
                                   startPoint: UnitPoint(x: -0.6 + phase * 0.8 + tilt.width * 0.4, y: tilt.height * 0.4),
                                   endPoint: UnitPoint(x: 0.9 + phase * 0.8 + tilt.width * 0.4, y: 1 + tilt.height * 0.4))
                        .opacity(0.4)
                        .blendMode(.colorDodge)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0.15), .init(color: .white, location: 0.5),
                                                   .init(color: .clear, location: 0.85)],
                                           startPoint: UnitPoint(x: phase - 0.3 + tilt.width * 0.3, y: 0),
                                           endPoint: UnitPoint(x: phase + 0.7 + tilt.width * 0.3, y: 1))
                        }
                    Canvas { c, size in
                        // 固定位置的星点，亮度随时间各自闪
                        var g = SplitMix(seed: 7)
                        for _ in 0..<70 {
                            let x = CGFloat(g.unit()) * size.width, y = CGFloat(g.unit()) * size.height
                            let a = 0.15 + 0.6 * (sin(t * 2.2 + Double(g.unit()) * 6.28) * 0.5 + 0.5)
                            c.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.6, height: 1.6)), with: .color(.white.opacity(a)))
                        }
                    }
                    .blendMode(.screen)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// 星点位置用的固定随机数
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func unit() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

/// 可以翻面的卡：点一下翻（带弹性的 3D 翻转）
struct FlippableCard: View {
    let pool: CardPool
    let card: CollectibleCard
    var width: CGFloat = 200
    @Binding var flipped: Bool
    var tilt: CGSize = .zero

    var body: some View {
        FlipBody(angle: flipped ? 180 : 0, pool: pool, card: card, width: width, tilt: tilt)
            .rotation3DEffect(.degrees(Double(tilt.width) * 12), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(Double(-tilt.height) * 12), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .animation(.spring(response: 0.55, dampingFraction: 0.72), value: flipped)
            .animation(.interpolatingSpring(stiffness: 120, damping: 14), value: tilt)
            .contentShape(Rectangle())
            .onTapGesture { flipped.toggle() }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(flipped ? "点一下翻回正面" : "点一下翻到背面")
    }
}

/// 翻转过程中按角度决定露出哪一面（转过 90° 才换到背面）
private struct FlipBody: View, Animatable {
    var angle: Double
    let pool: CardPool
    let card: CollectibleCard
    let width: CGFloat
    let tilt: CGSize

    nonisolated var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    var body: some View {
        let showBack = angle > 90
        Group {
            if showBack {
                CardFace(pool: pool, card: card, width: width, back: true)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                CardFace(pool: pool, card: card, width: width, tilt: tilt)
            }
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
    }
}
