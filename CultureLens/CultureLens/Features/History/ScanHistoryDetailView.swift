import SwiftData
import SwiftUI

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
            if let record {
                content(record)
            } else {
                ContentUnavailableView("找不到扫描记录", systemImage: "clock.badge.questionmark")
            }
        }
        .navigationTitle(record?.canonicalName ?? "历史扫描")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: record?.imageRelativePath) {
            imageData = await ScanMediaStore.shared.data(for: record?.imageRelativePath)
        }
    }

    private func content(_ record: ScanHistoryRecord) -> some View {
        ZStack {
            CulturePageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let imageData {
                        DataImageView(data: imageData)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 28))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(CultureTheme.cinnabar)

                        Text(record.canonicalName)
                            .font(.cultureSerif(.largeTitle))
                            .foregroundStyle(CultureTheme.inkPrimary)

                        Text(record.summary)
                            .font(.title3)
                            .foregroundStyle(CultureTheme.inkPrimary)
                            .lineSpacing(6)

                        HStack {
                            Label {
                                Text(
                                    record.confidence,
                                    format: .percent.precision(.fractionLength(0))
                                )
                            } icon: {
                                Image(systemName: "checkmark.seal")
                            }
                            Spacer()
                            Label(
                                record.placeName ?? "未记录位置",
                                systemImage: record.place == nil ? "location.slash" : "location"
                            )
                        }
                        .font(.subheadline)
                        .foregroundStyle(CultureTheme.inkSecondary)
                    }

                    if let result = resultSnapshot(for: record) {
                        CultureRelationGraphView(object: result.object)
                        savedCandidates(
                            result.displayAttractionCandidates,
                            selectedCandidateID: record.historySnapshot?.selectedCandidateID
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("识别记录")
                            .font(.headline)
                        Text("模型：\(record.modelIdentifier)")
                        Text("位置：\(record.placeName ?? "未使用")")
                        Text("类别：\(record.categoryRawValue)")
                    }
                    .font(.subheadline)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.vertical, 18)
            }
        }
    }

    @ViewBuilder
    private func savedCandidates(
        _ candidates: [RecognitionCandidate],
        selectedCandidateID: UUID?
    ) -> some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("附近景点候选")
                    .font(.cultureSerif(.title2))
                    .foregroundStyle(CultureTheme.inkPrimary)

                ForEach(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(candidate.canonicalName)
                                .font(.headline)
                                .foregroundStyle(CultureTheme.inkPrimary)
                            Spacer()
                            Label(
                                candidate.id == selectedCandidateID ? "最终确认" : "已保存",
                                systemImage: candidate.id == selectedCandidateID
                                    ? "checkmark.circle.fill"
                                    : "archivebox"
                            )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(CultureTheme.inkSecondary)
                        }
                        if let summary = candidate.informativeSummary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(CultureTheme.inkSecondary)
                        }
                        Label("附近景点候选", systemImage: "location.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CultureTheme.inkSecondary)
                    }
                    .padding(16)
                    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(CultureTheme.hairline, lineWidth: 1)
                    }
                }
            }
        }
    }

    private func resultSnapshot(for record: ScanHistoryRecord) -> RecognitionResult? {
        record.historySnapshot?.result ?? record.legacyResultSnapshot
    }
}

#Preview {
    NavigationStack {
        ScanHistoryDetailView(recordID: UUID())
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
