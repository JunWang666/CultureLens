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
    static let cardRadius: CGFloat = 22
}

extension Font {
    static func cultureSerif(_ style: Font.TextStyle) -> Font {
        .system(style, design: .serif, weight: .semibold)
    }
}
