import Foundation

nonisolated struct IlluminatedCity: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let scanCount: Int
}

nonisolated enum ExplorationBadgeKind: String, CaseIterable, Identifiable, Sendable {
  case firstLight
  case seriesBearer
  case cityLantern
  case fieldNotes
  case constellation
  case cultureKeeper

  var id: String { rawValue }

  var title: String {
    switch self {
    case .firstLight: String(localized: "初见微光")
    case .seriesBearer: String(localized: "成系之光")
    case .cityLantern: String(localized: "城市点灯人")
    case .fieldNotes: String(localized: "行走的笔记")
    case .constellation: String(localized: "十星成图")
    case .cultureKeeper: String(localized: "文化守望者")
    }
  }

  var detail: String {
    switch self {
    case .firstLight: String(localized: "点亮第一个文化节点")
    case .seriesBearer: String(localized: "点亮第一条文化系")
    case .cityLantern: String(localized: "在第一座城市留下文化足迹")
    case .fieldNotes: String(localized: "完成 5 次现场扫描")
    case .constellation: String(localized: "点亮 10 个文化节点")
    case .cultureKeeper: String(localized: "点亮 3 条文化系并走过 2 座城市")
    }
  }

}

nonisolated struct ExplorationBadge: Identifiable, Hashable, Sendable {
  let kind: ExplorationBadgeKind
  let isUnlocked: Bool

  var id: String { kind.id }
}

nonisolated struct ExplorationMilestoneSnapshot: Hashable, Sendable {
  let series: [ThemeProgress]
  let cities: [IlluminatedCity]
  let badges: [ExplorationBadge]
  let litNodeCount: Int
  let scanCount: Int

  var completedSeriesCount: Int {
    series.filter(\.isComplete).count
  }

  var unlockedBadgeCount: Int {
    badges.filter(\.isUnlocked).count
  }
}

nonisolated enum ExplorationMilestoneCalculator {
  static func snapshot(
    series: [ThemeProgress],
    history: [ScanHistoryRecordSnapshot],
    litNodeCount: Int
  ) -> ExplorationMilestoneSnapshot {
    let cities = illuminatedCities(from: history)
    let completedSeriesCount = series.filter(\.isComplete).count

    let badges = ExplorationBadgeKind.allCases.map { kind in
      let isUnlocked: Bool
      switch kind {
      case .firstLight:
        isUnlocked = litNodeCount >= 1
      case .seriesBearer:
        isUnlocked = completedSeriesCount >= 1
      case .cityLantern:
        isUnlocked = !cities.isEmpty
      case .fieldNotes:
        isUnlocked = history.count >= 5
      case .constellation:
        isUnlocked = litNodeCount >= 10
      case .cultureKeeper:
        isUnlocked = completedSeriesCount >= 3 && cities.count >= 2
      }
      return ExplorationBadge(kind: kind, isUnlocked: isUnlocked)
    }

    return ExplorationMilestoneSnapshot(
      series: series,
      cities: cities,
      badges: badges,
      litNodeCount: litNodeCount,
      scanCount: history.count
    )
  }

  static func illuminatedCities(
    from history: [ScanHistoryRecordSnapshot]
  ) -> [IlluminatedCity] {
    var countsByID: [String: Int] = [:]
    var namesByID: [String: String] = [:]

    for record in history {
      guard let city = normalizedCityName(record.placeName) else { continue }
      let id = city.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
      )
      countsByID[id, default: 0] += 1
      namesByID[id] = namesByID[id] ?? city
    }

    return countsByID.keys.compactMap { id in
      guard let name = namesByID[id], let count = countsByID[id] else { return nil }
      return IlluminatedCity(id: id, name: name, scanCount: count)
    }
    .sorted {
      if $0.scanCount != $1.scanCount {
        return $0.scanCount > $1.scanCount
      }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  static func normalizedCityName(_ placeName: String?) -> String? {
    guard let placeName else { return nil }
    let trimmed = placeName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let delimiters = CharacterSet(charactersIn: ",，·")
    let first = trimmed.components(separatedBy: delimiters).first?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first, !first.isEmpty else { return nil }
    return first
  }
}
