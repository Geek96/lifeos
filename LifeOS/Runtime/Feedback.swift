import Foundation

/// 统一反馈：底部提示条（可带撤销）+ 最近动态。
/// 原则：任何操作都要有反馈，不允许静默失败。
@Observable
@MainActor
final class Feedback {
    struct Toast: Identifiable {
        let id = UUID()
        var message: String
        var undo: (@MainActor () -> Void)?
        /// 按钮文字；nil 时为“撤销”
        var actionTitle: String?
    }

    struct Activity: Identifiable {
        let id = UUID()
        var message: String
        var date: Date
    }

    private(set) var toast: Toast?
    private(set) var activity: [Activity] = []
    private var dismissTask: Task<Void, Never>?

    /// 显示提示条（几秒后自动消失），同时记入最近动态。
    func show(_ message: String, undo: (@MainActor () -> Void)? = nil) {
        show(message, actionTitle: nil, action: undo)
    }

    /// 带一个动作按钮的提示条（例如“更新规则”）。
    func show(_ message: String, actionTitle: String?, action: (@MainActor () -> Void)?) {
        let undo = action
        toast = Toast(message: message, undo: action, actionTitle: actionTitle)
        log(message)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(undo == nil ? 4 : 8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        dismissTask?.cancel()
        toast = nil
    }

    /// 只记入最近动态，不弹提示条（用于后台完成的事）。
    func log(_ message: String) {
        activity.insert(Activity(message: message, date: Date()), at: 0)
        if activity.count > 20 { activity.removeLast(activity.count - 20) }
    }
}
