import SwiftUI

/// Resolves the first introduction image among a trip's lit objects for use as
/// the cultural-review hero (detail page + share card).
enum VisitTripHero {
  /// Walks trip objects in visit order and returns the first HTTPS image URL
  /// from each object's knowledge-pack introduction.
  static func imageURL(
    for trip: VisitTrip,
    store: KnowledgeStore? = KnowledgeStore.shared
  ) -> URL? {
    guard let store else { return nil }
    for object in trip.objects {
      let elementID = object.culturalElementID ?? object.id
      if let url = store.introductionDocument(elementID: elementID)?.imageBlocks.first?.imageURL {
        return url
      }
    }
    return nil
  }

  /// Fallback object used for poster-style artwork when no intro image exists.
  static func artworkObject(for trip: VisitTrip) -> CultureObject {
    trip.objects.first
      ?? CultureObject(
        id: trip.id,
        canonicalName: trip.title,
        summary: "",
        category: .other,
        timePeriod: nil,
        region: trip.placeNames.first,
        confidence: 1,
        artworkSymbol: "book.closed.fill",
        concepts: [],
        relations: [],
        sources: []
      )
  }
}

/// Full-width magazine hero for a visit trip — intro photo when available,
/// otherwise poster-style `ObjectArtwork`.
struct VisitTripHeroView: View {
  let trip: VisitTrip
  var height: CGFloat = 240
  var imageURL: URL? = nil

  private var resolvedURL: URL? {
    imageURL ?? VisitTripHero.imageURL(for: trip)
  }

  var body: some View {
    Group {
      if let resolvedURL {
        CachedAsyncImage(
          url: resolvedURL,
          transaction: Transaction(animation: .easeOut(duration: 0.3))
        ) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFill()
              .frame(maxWidth: .infinity)
              .frame(height: height)
              .clipped()
              .magazinePhoto()
              .transition(.opacity)
          case .failure:
            posterFallback
          case .empty:
            Rectangle()
              .fill(CultureTheme.inkPrimary.opacity(0.08))
              .frame(maxWidth: .infinity)
              .frame(height: height)
          @unknown default:
            posterFallback
          }
        }
      } else {
        posterFallback
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .accessibilityLabel("\(trip.title)主图")
  }

  private var posterFallback: some View {
    ObjectArtwork(object: VisitTripHero.artworkObject(for: trip), height: height)
  }
}
