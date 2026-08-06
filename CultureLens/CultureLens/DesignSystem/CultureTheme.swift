import SwiftUI

enum CultureTheme {
    static let canvas = Color("Canvas")
    static let surface = Color("Surface")
    static let inkPrimary = Color("InkPrimary")
    static let inkSecondary = Color("InkSecondary")
    static let cinnabar = Color("Cinnabar")
    static let antiqueGold = Color("AntiqueGold")
    static let hairline = inkPrimary.opacity(0.12)

    static let pagePadding: CGFloat = 20
    /// 杂志分栏间距（栏目与栏目之间）。
    static let sectionSpacing: CGFloat = 32
    /// 列表行内上下留白（配合细线分隔）。
    static let rowPadding: CGFloat = 16
    /// 仅用于分享卡、对话气泡、墨色封面等确需盒子的场景。
    static let cardRadius: CGFloat = 22
}
