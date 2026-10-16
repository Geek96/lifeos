import SwiftUI

/// 底部提示条：每个操作的反馈都从这里出来，可带“撤销”。
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.feedback.toast {
            HStack(spacing: 12) {
                Text(toast.message)
                    .lineLimit(2)
                if let undo = toast.undo {
                    Button(toast.actionTitle ?? "撤销") {
                        undo()
                        model.feedback.dismissToast()
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.callout)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(.separator))
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
            .accessibilityAddTraits(.isStaticText)
        }
    }
}

/// 状态标签：图标 + 文字，颜色从不单独表达含义。
struct StatusTag: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .tagCapsule(tint, horizontal: 7, vertical: 2)
    }
}
