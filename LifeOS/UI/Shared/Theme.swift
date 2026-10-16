import SwiftUI
import AppKit
import LifeOSCore

/// 视觉规范：圆角、间距、语义色。各处统一从这里取，不手写数值。
/// 沿用 CourseOS 的视觉规范（docs/specs/2026-10-10-polish-design.md §2）。
enum Theme {
    enum Radius {
        /// 标签、输入框
        static let small: CGFloat = 6
        /// 卡片
        static let card: CGFloat = 10
        /// 大面板
        static let panel: CGFloat = 12
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // 可读的语义色：系统橙 / 绿 / 青在白底只有约 2:1，小字达不到 WCAG 4.5:1。
    // 浅色用深一档、深色用亮一档；背景色块（opacity）仍可用系统色。
    static let red = dynamic(light: 0xC62828, dark: 0xFF7A7A)
    static let orange = dynamic(light: 0x9A4708, dark: 0xFFB454)
    static let green = dynamic(light: 0x126B34, dark: 0x5EE08A)
    static let purple = dynamic(light: 0x7E22CE, dark: 0xC99BFF)
    static let teal = dynamic(light: 0x0F766E, dark: 0x4FD1C5)

    static let blue = dynamic(light: 0x1D4ED8, dark: 0x7CB4FF)
    static let indigo = dynamic(light: 0x4338CA, dark: 0xA5B4FC)

    /// 每种出现的颜色：生活事项用蓝/橙/绿，课程图层用灰/靛/紫/青，一眼分开“我的事”和“课上的事”
    static func tint(_ style: Occurrence.Style) -> Color {
        switch style {
        case .event: return blue
        case .deadline: return orange
        case .window: return green
        case .classSession: return .secondary
        case .courseDue: return indigo
        case .courseExam: return purple
        case .courseOptional: return teal
        }
    }

    static func icon(_ style: Occurrence.Style) -> String {
        switch style {
        case .event: return "calendar"
        case .deadline: return "flag"
        case .window: return "arrow.left.and.right"
        case .classSession: return "graduationcap"
        case .courseDue: return "doc.text"
        case .courseExam: return "pencil.and.list.clipboard"
        case .courseOptional: return "sparkles"
        }
    }

    static func load(_ level: DayLoad.Level) -> Color {
        switch level { case .light: return green; case .normal: return .secondary; case .busy: return orange }
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        func ns(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? ns(dark) : ns(light)
        })
    }
}

/// 外观：跟随系统 / 浅色 / 深色（设置 → 通用）。
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appearance"
    var id: String { rawValue }
    var label: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

/// 彩色胶囊标签：在选中行（主色背景）上自动改成白色系，保证可读。
struct TagCapsule: ViewModifier {
    let tint: Color
    var horizontal: CGFloat = 6
    var vertical: CGFloat = 1
    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        let onSelection = prominence == .increased
        content
            .padding(.horizontal, horizontal).padding(.vertical, vertical)
            .foregroundStyle(onSelection ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            .background(onSelection ? AnyShapeStyle(Color.white.opacity(0.22)) : AnyShapeStyle(tint.opacity(0.12)), in: Capsule())
    }
}

/// 彩色文字：选中行上改成白色。
struct SelectionAwareTint: ViewModifier {
    let tint: Color
    @Environment(\.backgroundProminence) private var prominence

    func body(content: Content) -> some View {
        content.foregroundStyle(prominence == .increased ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
    }
}

/// 浅色卡片背景
struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.Space.m

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

extension View {
    func tagCapsule(_ tint: Color, horizontal: CGFloat = 6, vertical: CGFloat = 1) -> some View {
        modifier(TagCapsule(tint: tint, horizontal: horizontal, vertical: vertical))
    }

    func selectionAwareTint(_ tint: Color) -> some View { modifier(SelectionAwareTint(tint: tint)) }

    func card(padding: CGFloat = Theme.Space.m) -> some View { modifier(CardBackground(padding: padding)) }
}
