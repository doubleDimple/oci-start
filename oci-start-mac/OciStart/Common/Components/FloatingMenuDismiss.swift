import Foundation

/// 统一关闭各业务页的窗内操作菜单浮层。
/// 残留 panel / ClickCatcher 会盖住整窗（控制台/SSH/侧栏按钮全无响应）。
@MainActor
enum FloatingMenuDismiss {
    static func all() {
        InstanceActionMenuPresenter.shared.dismiss()
        BootActionMenuPresenter.shared.dismiss()
        TenantActionMenuPresenter.shared.dismiss()
    }
}
