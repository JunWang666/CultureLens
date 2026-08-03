import UIKit

// 隐藏系统返回键（如 ScanResultView 的自定义返回按钮）时，UIKit 会一并关闭
// 屏幕左边缘的侧滑返回手势；这里恢复它，仅在栈深度大于 1 且无模态覆盖时生效。
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1 && presentedViewController == nil
    }
}
