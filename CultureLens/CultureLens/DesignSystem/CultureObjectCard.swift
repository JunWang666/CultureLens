import SwiftUI
import UIKit

/// Shareable culture card used by object detail and cultural review.
struct CultureObjectCard: View {
  let object: CultureObject
  var showsBrandMark: Bool = false
  var artworkHeight: CGFloat = 132

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topTrailing) {
        ObjectArtwork(object: object, height: artworkHeight)

        if showsBrandMark {
          Text("CultureLens")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(12)
        }
      }

      VStack(alignment: .leading, spacing: 8) {
        Text(object.canonicalName)
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)

        Text(
          [object.category.rawValue, object.timePeriod, object.region]
            .compactMap { $0 }
            .joined(separator: " · ")
        )
        .font(.caption)
        .foregroundStyle(CultureTheme.cinnabar)
        .lineLimit(1)

        Text(object.summary)
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineLimit(3)
      }
      .padding(16)
    }
    .background(CultureTheme.surface)
    .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .contentShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityHint("打开文化对象详情")
  }
}

/// Renders `CultureObjectCard` for the system share sheet.
@MainActor
enum CultureCardShareRenderer {
  static func image(for object: CultureObject, width: CGFloat = 360) -> UIImage? {
    let card = CultureObjectCard(object: object, showsBrandMark: true, artworkHeight: 160)
      .frame(width: width)
      .environment(\.colorScheme, .light)

    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    return renderer.uiImage
  }

  static func shareText(for object: CultureObject) -> String {
    let meta = [object.category.rawValue, object.timePeriod, object.region]
      .compactMap { $0 }
      .joined(separator: " · ")
    if meta.isEmpty {
      return "\(object.canonicalName)\n\(object.summary)\n— CultureLens"
    }
    return "\(object.canonicalName)\n\(meta)\n\(object.summary)\n— CultureLens"
  }
}

