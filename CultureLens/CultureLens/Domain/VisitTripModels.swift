import Foundation

/// A visit clustered from flat scan history by time proximity and place.
nonisolated struct VisitTrip: Identifiable, Hashable, Sendable {
  let id: UUID
  let recordIDs: [UUID]
  let startedAt: Date
  let endedAt: Date
  let title: String
  let placeNames: [String]
  let litNodeCount: Int
  let attractionNames: [String]
  let newRelationCount: Int
  let objects: [CultureObject]

  var scanCount: Int { recordIDs.count }

  var durationText: String {
    let formatter = DateIntervalFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: startedAt, to: endedAt)
  }
}

/// Clusters chronological scan records into visits (行程).
nonisolated enum VisitTripBuilder {
  /// Consecutive scans farther apart than this start a new trip.
  static let maxGapSeconds: TimeInterval = 3 * 60 * 60
  /// Scans within this radius stay in the same trip when place names differ.
  static let maxPlaceDistanceMeters: Double = 2_000

  static func cluster(
    _ records: [ScanHistoryRecordSnapshot]
  ) -> [VisitTrip] {
    let ordered = records.sorted { $0.createdAt < $1.createdAt }
    guard !ordered.isEmpty else { return [] }

    var groups: [[ScanHistoryRecordSnapshot]] = [[ordered[0]]]
    for record in ordered.dropFirst() {
      let previous = groups[groups.count - 1].last!
      if belongsTogether(previous, record) {
        groups[groups.count - 1].append(record)
      } else {
        groups.append([record])
      }
    }

    return groups.reversed().map(makeTrip)
  }

  private static func belongsTogether(
    _ earlier: ScanHistoryRecordSnapshot,
    _ later: ScanHistoryRecordSnapshot
  ) -> Bool {
    guard later.createdAt.timeIntervalSince(earlier.createdAt) <= maxGapSeconds else {
      return false
    }

    if let left = earlier.placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
      let right = later.placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
      !left.isEmpty,
      !right.isEmpty
    {
      if left == right { return true }
    }

    if let lat1 = earlier.latitude,
      let lon1 = earlier.longitude,
      let lat2 = later.latitude,
      let lon2 = later.longitude
    {
      let distance = KnowledgeStore.haversineDistanceMeters(
        fromLatitude: lat1,
        fromLongitude: lon1,
        toLatitude: lat2,
        toLongitude: lon2
      )
      return distance <= maxPlaceDistanceMeters
    }

    // Missing location: keep joining while time gap is small.
    return earlier.latitude == nil || later.latitude == nil
  }

  private static func makeTrip(_ group: [ScanHistoryRecordSnapshot]) -> VisitTrip {
    let started = group.first!.createdAt
    let ended = group.last!.createdAt
    let placeNames = uniquePreservingOrder(
      group.compactMap { name in
        let trimmed = name.placeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
      }
    )

    var litKeys = Set<String>()
    var litIDs = Set<UUID>()
    var attractionNames: [String] = []
    var seenAttractions = Set<String>()
    var relationIDs = Set<UUID>()
    var objects: [CultureObject] = []
    var seenObjectIDs = Set<UUID>()

    for record in group {
      if let key = record.culturalElementKey, !key.isEmpty {
        litKeys.insert(key)
      } else {
        litIDs.insert(record.cultureObjectID)
      }

      if let object = record.object {
        if seenObjectIDs.insert(object.id).inserted {
          objects.append(object)
        }
        for relation in object.relations {
          relationIDs.insert(relation.id)
        }
      }

      if let place = record.placeName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !place.isEmpty,
        seenAttractions.insert(place).inserted
      {
        attractionNames.append(place)
      }
      if let attraction = record.attractionName?.trimmingCharacters(in: .whitespacesAndNewlines),
        !attraction.isEmpty,
        seenAttractions.insert(attraction).inserted
      {
        attractionNames.append(attraction)
      }
    }

    let title: String
    if let firstPlace = placeNames.first {
      title = firstPlace
    } else if let firstName = group.first?.canonicalName {
      title = "围绕「\(firstName)」的参观"
    } else {
      title = "文化参观"
    }

    return VisitTrip(
      id: group.first!.recordID,
      recordIDs: group.map(\.recordID),
      startedAt: started,
      endedAt: ended,
      title: title,
      placeNames: placeNames,
      litNodeCount: litKeys.count + litIDs.count,
      attractionNames: attractionNames,
      newRelationCount: relationIDs.count,
      objects: objects
    )
  }

  private static func uniquePreservingOrder(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
      result.append(value)
    }
    return result
  }
}

/// Lightweight history row used for trip clustering without SwiftData coupling.
nonisolated struct ScanHistoryRecordSnapshot: Hashable, Sendable {
  let recordID: UUID
  let createdAt: Date
  let cultureObjectID: UUID
  let canonicalName: String
  let placeName: String?
  let latitude: Double?
  let longitude: Double?
  let culturalElementKey: String?
  let attractionName: String?
  let object: CultureObject?

  init(
    recordID: UUID,
    createdAt: Date,
    cultureObjectID: UUID,
    canonicalName: String,
    placeName: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    culturalElementKey: String? = nil,
    attractionName: String? = nil,
    object: CultureObject? = nil
  ) {
    self.recordID = recordID
    self.createdAt = createdAt
    self.cultureObjectID = cultureObjectID
    self.canonicalName = canonicalName
    self.placeName = placeName
    self.latitude = latitude
    self.longitude = longitude
    self.culturalElementKey = culturalElementKey
    self.attractionName = attractionName
    self.object = object
  }
}

extension ScanHistoryRecord {
  var tripSnapshot: ScanHistoryRecordSnapshot {
    let saved = savedObject
    let attractionName: String?
    if historySnapshot?.result.resolutionStatus == "attraction" {
      attractionName = saved?.canonicalName
    } else {
      attractionName = nil
    }
    return ScanHistoryRecordSnapshot(
      recordID: recordID,
      createdAt: createdAt,
      cultureObjectID: cultureObjectID,
      canonicalName: canonicalName,
      placeName: placeName,
      latitude: latitude,
      longitude: longitude,
      culturalElementKey: saved?.culturalElementKey,
      attractionName: attractionName,
      object: saved
    )
  }
}
