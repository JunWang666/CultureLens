import Foundation

/// Resolves knowledge-pack introduction photos for culture objects / visit heroes.
enum CultureObjectImage {
  /// First HTTPS image in the element's introduction body (`imageBlocks.first`).
  static func introductionURL(
    for object: CultureObject,
    store: KnowledgeStore? = KnowledgeStore.shared
  ) -> URL? {
    guard let store else { return nil }

    var seen = Set<UUID>()
    for candidate in [object.culturalElementID, object.id].compactMap({ $0 }) {
      guard seen.insert(candidate).inserted else { continue }
      if let url = store.introductionDocument(elementID: candidate)?.imageBlocks.first?.imageURL {
        return url
      }
    }

    // History / unbound rows may only carry a display name.
    if let matched = store.elementID(matchingName: object.canonicalName),
      seen.insert(matched).inserted,
      let url = store.introductionDocument(elementID: matched)?.imageBlocks.first?.imageURL
    {
      return url
    }

    return nil
  }

  /// First introduction image among trip objects, in visit order.
  static func introductionURL(
    for trip: VisitTrip,
    store: KnowledgeStore? = KnowledgeStore.shared
  ) -> URL? {
    for object in trip.objects {
      if let url = introductionURL(for: object, store: store) {
        return url
      }
    }
    return nil
  }
}
