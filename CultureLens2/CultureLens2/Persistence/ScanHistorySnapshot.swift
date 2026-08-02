import Foundation

struct ScanHistorySnapshot: Codable, Hashable, Sendable {
    let result: RecognitionResult
    let selectedObject: CultureObject
    let selectedCandidateID: UUID?
}

extension ScanHistoryRecord {
    var historySnapshot: ScanHistorySnapshot? {
        try? JSONDecoder().decode(ScanHistorySnapshot.self, from: resultSnapshotData)
    }

    var legacyResultSnapshot: RecognitionResult? {
        try? JSONDecoder().decode(RecognitionResult.self, from: resultSnapshotData)
    }

    var savedObject: CultureObject? {
        historySnapshot?.selectedObject ?? legacyResultSnapshot?.object
    }
}
