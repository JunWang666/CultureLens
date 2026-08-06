import Foundation
import Testing

@testable import CultureLens

struct ExplorationMilestoneTests {
  @Test func cityNamesAreNormalizedAndDeduplicated() {
    let history = [
      historyRecord(placeName: "杭州，中国"),
      historyRecord(placeName: "杭州, 浙江, 中国"),
      historyRecord(placeName: "良渚·杭州"),
      historyRecord(placeName: "  "),
      historyRecord(placeName: nil),
    ]

    let cities = ExplorationMilestoneCalculator.illuminatedCities(from: history)

    #expect(cities.map(\.name) == ["杭州", "良渚"])
    #expect(cities.map(\.scanCount) == [2, 1])
  }

  @Test func milestonesUnlockFromExistingProgressAndHistory() {
    let completedSeries = (0..<3).map { index in
      let ids = [UUID(), UUID()]
      let theme = KnowledgePack.Theme(
        id: UUID(),
        name: "文化系 \(index)",
        summary: "",
        elementIds: ids,
        minContacted: 2
      )
      return ThemeProgress(
        theme: theme,
        elementIds: ids,
        contactedIds: ids,
        remainingIds: []
      )
    }
    let history = [
      historyRecord(placeName: "杭州，中国"),
      historyRecord(placeName: "杭州，中国"),
      historyRecord(placeName: "南京，中国"),
      historyRecord(placeName: "南京，中国"),
      historyRecord(placeName: "南京，中国"),
    ]

    let snapshot = ExplorationMilestoneCalculator.snapshot(
      series: completedSeries,
      history: history,
      litNodeCount: 10
    )

    #expect(snapshot.completedSeriesCount == 3)
    #expect(snapshot.cities.count == 2)
    #expect(snapshot.unlockedBadgeCount == ExplorationBadgeKind.allCases.count)
    #expect(snapshot.badges.filter(\.isUnlocked).count == snapshot.badges.count)
  }

  @Test func emptyProgressKeepsEveryBadgeLocked() {
    let snapshot = ExplorationMilestoneCalculator.snapshot(
      series: [],
      history: [],
      litNodeCount: 0
    )

    #expect(snapshot.completedSeriesCount == 0)
    #expect(snapshot.cities.isEmpty)
    #expect(snapshot.badges.filter(\.isUnlocked).isEmpty)
  }

  private func historyRecord(placeName: String?) -> ScanHistoryRecordSnapshot {
    ScanHistoryRecordSnapshot(
      recordID: UUID(),
      createdAt: .now,
      cultureObjectID: UUID(),
      canonicalName: "测试对象",
      placeName: placeName
    )
  }
}
