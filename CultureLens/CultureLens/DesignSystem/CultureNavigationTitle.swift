import SwiftUI
import UIKit

/// iPad 上将导航标题放到返回键右侧，布局与 `ScanResultView` 一致。
/// iPhone 保持系统居中 inline 标题；有副标题时用 `.principal`。
///
/// 两个坑：1) Button 和 Text 不能混在一个 HStack 里做 toolbar item（iOS 18+
/// 布局 bug，后面的子视图不渲染）；2) iOS 26 会把相邻 toolbar item 合并进同一个
/// 玻璃共享背景，标题需要用 sharedBackgroundVisibility(.hidden) 摘出来保持纯文本样式。
struct CultureNavigationTitleModifier: ViewModifier {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var showsBackButton: Bool = true
    var backSystemImage: String = "chevron.backward"
    var backAccessibilityLabel: LocalizedStringKey = "返回"
    /// `nil` 时仅 iPad 使用 leading 标题；`true` 强制全平台（如扫描结果页）。
    var prefersLeadingTitle: Bool? = nil
    var accessibilityIdentifier: String? = nil

    @Environment(\.dismiss) private var dismiss

    private var usesLeadingTitle: Bool {
        if let prefersLeadingTitle {
            return prefersLeadingTitle
        }
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    func body(content: Content) -> some View {
        if usesLeadingTitle {
            content
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(showsBackButton)
                .toolbar {
                    if showsBackButton {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                dismiss()
                            } label: {
                                Label(backAccessibilityLabel, systemImage: backSystemImage)
                                    .labelStyle(.iconOnly)
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }

                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .topBarLeading) {
                            leadingTitle
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            leadingTitle
                        }
                    }
                }
        } else if let subtitle {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(title)
                                .font(.headline)
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(CultureTheme.inkSecondary)
                        }
                    }
                }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    // fixedSize 是必须的：iOS 26 toolbar item 可能分到比内容小的宽度导致文字被截断
    @ViewBuilder
    private var leadingTitle: some View {
        Group {
            if let subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(CultureTheme.inkPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(CultureTheme.inkSecondary)
                }
            } else {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(CultureTheme.inkPrimary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) {
        self.identifier = identifier
    }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

extension View {
    /// 通用导航标题：iPad 在返回键右侧，iPhone 居中。
    func cultureNavigationTitle(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey? = nil,
        showsBackButton: Bool = true,
        backSystemImage: String = "chevron.backward",
        backAccessibilityLabel: LocalizedStringKey = "返回",
        prefersLeadingTitle: Bool? = nil,
        accessibilityIdentifier: String? = nil
    ) -> some View {
        modifier(
            CultureNavigationTitleModifier(
                title: title,
                subtitle: subtitle,
                showsBackButton: showsBackButton,
                backSystemImage: backSystemImage,
                backAccessibilityLabel: backAccessibilityLabel,
                prefersLeadingTitle: prefersLeadingTitle,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }
}
