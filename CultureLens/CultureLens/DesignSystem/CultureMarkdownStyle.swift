import SwiftStreamingMarkdown
import SwiftUI
import UIKit

/// 讲解 / 问答 Markdown：字体全部来自 `CultureTypography`。
enum CultureMarkdownStyle {
  static func renderConfig(animated: Bool) -> MarkdownRenderConfig {
    let ink = CultureTheme.inkPrimary
    let secondary = CultureTheme.inkSecondary
    let cinnabar = CultureTheme.cinnabar

    let body = textFonts(
      size: CultureTypography.scaledPointSize(for: .body),
      lineHeight: CultureTypography.scaledSize(26)
    )
    let callout = textFonts(
      size: CultureTypography.scaledPointSize(for: .callout),
      lineHeight: CultureTypography.scaledSize(24)
    )
    let small = textFonts(
      size: CultureTypography.scaledPointSize(for: .subheadline),
      lineHeight: CultureTypography.scaledSize(22)
    )

    return MarkdownRenderConfig.default
      .withShouldAnimateText(value: animated)
      .withParagraphStyle(
        value: .init(textFonts: body, textColor: ink)
      )
      .withOrderedListStyle(
        value: .init(textFonts: body, textColor: ink)
      )
      .withBlockQuoteStyle(
        value: .init(textFonts: callout, textColor: secondary)
      )
      .withHeadingStyle(
        value: .init(
          h1Font: headingFonts(size: CultureTypography.scaledPointSize(for: .title)),
          h2Font: headingFonts(size: CultureTypography.scaledSize(24)),
          h3Font: headingFonts(size: CultureTypography.scaledPointSize(for: .title3)),
          h4Font: headingFonts(size: CultureTypography.scaledSize(18)),
          h5Font: headingFonts(size: CultureTypography.scaledPointSize(for: .headline)),
          h6Font: headingFonts(size: CultureTypography.scaledPointSize(for: .subheadline)),
          textColor: ink
        )
      )
      .withInlineStyle(
        value: .init(
          boldTextColor: ink,
          linkTextFont: mdFont(size: CultureTypography.pointSize(for: .body))
            ?? .systemFont(
              ofSize: CultureTypography.scaledPointSize(for: .body),
              weight: .regular
            ),
          linkTextColor: cinnabar,
          codeTextFont: .monospacedSystemFont(
            ofSize: CultureTypography.scaledSize(15),
            weight: .regular
          ),
          codeTextColor: secondary,
          codeBackgroundColor: CultureTheme.canvas.opacity(0.9),
          codeUnderlineColor: CultureTheme.hairline
        )
      )
      .withTableStyle(
        value: .init(
          textFonts: small,
          headerTextColor: ink,
          regularTextColor: secondary,
          headerBackgroundColor: CultureTheme.canvas,
          borderColor: CultureTheme.hairline,
          actionButtonColor: cinnabar
        )
      )
  }

  private static func textFonts(size: CGFloat, lineHeight: CGFloat) -> TextFonts {
    let normal = mdFont(size: size) ?? .systemFont(ofSize: size, weight: .regular)
    let bold = mdFont(size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    return TextFonts(
      normal: normal,
      italic: nil,
      bold: bold,
      boldItalic: nil,
      preferredLetterSpacing: nil,
      preferredLineHeight: lineHeight
    )
  }

  private static func headingFonts(size: CGFloat) -> TextFonts {
    let font = mdFont(size: size) ?? .systemFont(ofSize: size, weight: .semibold)
    return TextFonts(
      normal: font,
      italic: nil,
      bold: font,
      boldItalic: nil,
      preferredLetterSpacing: nil,
      preferredLineHeight: size * 1.25
    )
  }

  private static func mdFont(size: CGFloat) -> MDFont? {
    CultureTypography.markdownFont(size: size)
  }
}
