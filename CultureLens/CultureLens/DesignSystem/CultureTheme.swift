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

    /// 杂志标题宋体：优先内置的思源宋体子集，其次设备上的 Songti SC，
    /// 都没有才回退系统衬线（中文会再退成黑体，效果最差）。
    static func magazineDisplay(_ style: Font.TextStyle) -> Font {
        if let name = CultureThemeFonts.magazineSerifName {
            return .custom(name, size: 17, relativeTo: style)
        }
        return .cultureSerif(style)
    }

    /// 固定字号的展示宋体（刊头、封面标题、巨型字符水印）。
    static func magazineDisplay(size: CGFloat) -> Font {
        if let name = CultureThemeFonts.magazineSerifName {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .semibold, design: .serif)
    }
}

enum CultureThemeFonts {
    /// 内置思源宋体（子集化 SemiBold）在 bundle 里的文件名与 PostScript 名。
    /// OFL 的 Reserved Font Name 约束要求子集化/改名后不得沿用 Noto 名称。
    private static let bundledFontResource = "CultureLensSerif-SemiBold"
    private static let bundledFontPostScriptName = "CultureLensSerif-SemiBold"

    /// 首次访问时注册内置字体；`UIFont(name:)` 探测最终结果。
    /// 返回 nil 表示没有任何可用宋体，调用方回退系统衬线。
    static let magazineSerifName: String? = {
        #if canImport(UIKit)
        if let url = Bundle.main.url(forResource: bundledFontResource, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        if UIFont(name: bundledFontPostScriptName, size: 12) != nil {
            return bundledFontPostScriptName
        }
        if UIFont(name: "Songti SC", size: 12) != nil {
            return "Songti SC"
        }
        #endif
        return nil
    }()
}
