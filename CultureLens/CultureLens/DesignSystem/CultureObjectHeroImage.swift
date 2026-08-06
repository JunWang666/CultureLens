import SwiftUI
import UIKit

/// Object artwork that prefers the first introduction-body photo, then poster fallback.
///
/// Pins width+height before `scaledToFill` (same clip pattern as scan result photos)
/// so fill cannot expand past the card / column bounds.
struct CultureObjectHeroImage: View {
  let object: CultureObject
  var height: CGFloat = 132
  var imageURL: URL? = nil
  /// Sync image for `ImageRenderer` share export (async load won't finish in time).
  var preloadedImage: UIImage? = nil

  @State private var resolvedURL: URL?

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .overlay {
        content
      }
      .clipped()
      .task(id: object.id) {
        guard preloadedImage == nil else { return }
        resolvedURL = imageURL ?? CultureObjectImage.introductionURL(for: object)
        if resolvedURL == nil {
          _ = await KnowledgePackLoader.shared.store()
          resolvedURL = imageURL ?? CultureObjectImage.introductionURL(for: object)
        }
      }
      .accessibilityLabel("\(object.canonicalName)示意图")
  }

  @ViewBuilder
  private var content: some View {
    if let preloadedImage {
      Image(uiImage: preloadedImage)
        .resizable()
        .scaledToFill()
        .magazinePhoto()
    } else if let resolvedURL {
      CachedAsyncImage(
        url: resolvedURL,
        transaction: Transaction(animation: .easeOut(duration: 0.3))
      ) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
            .magazinePhoto()
            .transition(.opacity)
        case .failure:
          ObjectArtwork(object: object, height: height)
        case .empty:
          Rectangle()
            .fill(CultureTheme.inkPrimary.opacity(0.08))
        @unknown default:
          ObjectArtwork(object: object, height: height)
        }
      }
    } else {
      ObjectArtwork(object: object, height: height)
    }
  }
}
