import SwiftData
import SwiftUI

/// 足迹历史详情：从历史记录重建扫描会话，复用扫描结果页展示。
struct ScanHistoryDetailView: View {
    let recordID: UUID

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]
    @State private var imageData: Data?

    private var record: ScanHistoryRecord? {
        records.first { $0.recordID == recordID }
    }

    var body: some View {
        Group {
            if let record, let result = resolvedResult(for: record) {
                ScanResultView(
                    session: ScanSession(
                        id: record.recordID,
                        imageData: imageData ?? Data(),
                        result: result,
                        place: record.place,
                        createdAt: record.createdAt,
                        isDemo: record.modelIdentifier == "culturelens-sample-v1"
                    ),
                    presentation: .history
                )
            } else {
                ContentUnavailableView("找不到扫描记录", systemImage: "clock.badge.questionmark")
                    .cultureNavigationTitle("历史扫描")
            }
        }
        .task(id: record?.imageRelativePath) {
            imageData = await ScanMediaStore.shared.data(for: record?.imageRelativePath)
        }
    }

    /// 快照里的 `result.object` 是最初主结果；展示用户最终查看/保存的对象。
    private func resolvedResult(for record: ScanHistoryRecord) -> RecognitionResult? {
        if let snapshot = record.historySnapshot {
            var result = snapshot.result
            result.object = snapshot.selectedObject
            return result
        }
        return record.legacyResultSnapshot
    }
}

#Preview {
    NavigationStack {
        ScanHistoryDetailView(recordID: UUID())
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
