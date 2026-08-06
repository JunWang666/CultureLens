import SwiftUI

/// 详情页自适应布局。
///
/// iPad 横屏（regular 宽度且宽大于高）时内容切换为左右分栏：
/// `leading` 一栏放标题、图片与身份信息，`trailing` 一栏放其余内容。
/// 分栏时 `isWide` 为 true，页面可借此调整内容（例如把大标题提到
/// 栏顶、加高图片）。其余情况（iPhone、iPad 竖屏）保持原有单列布局。
struct SplitDetailLayout<Leading: View, Trailing: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var topPadding: CGFloat = 16
    var bottomPadding: CGFloat = 40
    /// 单列时的内容最大宽度（nil 表示撑满）。
    var contentMaxWidth: CGFloat?
    @ViewBuilder var leading: (_ isWide: Bool) -> Leading
    @ViewBuilder var trailing: (_ isWide: Bool) -> Trailing

    var body: some View {
        GeometryReader { proxy in
            let isWide = horizontalSizeClass == .regular
                && proxy.size.width > proxy.size.height
            let leadingWidth = min(proxy.size.width * 0.38, 440)

            ScrollView {
                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: 32) {
                            VStack(alignment: .leading, spacing: 24) {
                                leading(true)
                            }
                            .frame(width: leadingWidth, alignment: .leading)

                            VStack(alignment: .leading, spacing: 24) {
                                trailing(true)
                            }
                            // minWidth: 0 lets wide children (e.g. graph canvas)
                            // compress instead of pushing the trailing column off-screen.
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        }
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(CultureTheme.hairline)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.leading, leadingWidth + 15.5)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 24) {
                            leading(false)
                            trailing(false)
                        }
                        .frame(minWidth: 0, maxWidth: contentMaxWidth ?? .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.top, topPadding)
                .padding(.bottom, bottomPadding)
            }
        }
    }
}
