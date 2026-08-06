import Foundation

/// Names for the poster-style exploration artwork shipped with the app.
enum ExplorationArtwork {
  private static let namespace = "ExplorationArtwork"

  private static let illustratedThemeKeys: Set<String> = [
    "city-water-rice",
    "prehistoric-civilization-dawn",
    "jade-ritual-heaven",
    "institutions-and-exchanges",
    "west-lake-ten-scenes-gaze",
    "wuyue-swords-and-pagodas",
    "pagoda-lake-silhouette",
    "literati-and-elegant-objects",
    "moon-pools-reflection",
    "dynasty-timeline",
    "hundred-schools-thought",
    "prosperity-and-decline",
    "jiangnan-lifeways",
    "how-liangzhu-was-seen",
    "top-ten-treasures-trail",
    "causeway-governance-poetry",
  ]

  static func seriesImageName(for theme: KnowledgePack.Theme) -> String {
    guard let key = theme.key, illustratedThemeKeys.contains(key) else {
      return "\(namespace)/Series-fallback"
    }
    return "\(namespace)/Series-\(key)"
  }

  static func badgeImageName(for kind: ExplorationBadgeKind) -> String {
    "\(namespace)/Badge-\(kind.rawValue)"
  }
}
