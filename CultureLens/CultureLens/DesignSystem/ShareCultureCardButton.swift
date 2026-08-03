import SwiftUI

/// Toolbar / inline control that shares a rendered `CultureObjectCard`.
struct ShareCultureCardButton: View {
  let object: CultureObject
  var label: ShareLabel = .icon

  enum ShareLabel {
    case icon
    case titled
  }

  @State private var shareItem: CultureCardShareItem?

  var body: some View {
    Group {
      if let shareItem {
        ShareLink(
          item: shareItem,
          preview: SharePreview(
            object.canonicalName,
            image: shareItem.image.map(Image.init(uiImage:))
          )
        ) {
          labelView
        }
        .accessibilityLabel("分享文化卡片")
      } else {
        ProgressView()
          .controlSize(.small)
      }
    }
    .task(id: object.id) {
      let image = CultureCardShareRenderer.image(for: object)
      shareItem = CultureCardShareItem(object: object, image: image)
    }
  }

  @ViewBuilder
  private var labelView: some View {
    switch label {
    case .icon:
      Image(systemName: "square.and.arrow.up")
    case .titled:
      Label("分享文化卡片", systemImage: "square.and.arrow.up")
        .frame(maxWidth: .infinity)
    }
  }
}
