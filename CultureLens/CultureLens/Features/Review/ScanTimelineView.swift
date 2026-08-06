import SwiftData
import SwiftUI

/// Chronological scan footprint list (formerly a mode inside `CultureMapView`).
struct ScanTimelineView: View {
    var startScan: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    var body: some View {
        if records.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(records) { record in
                        NavigationLink(value: AppRoute.history(record.recordID)) {
                            historyCard(record)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("删除记录", role: .destructive) {
                                delete(record)
                            }
                        }
                    }
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .safeAreaPadding(.top, 4)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有扫描足迹", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("完成一次扫描并确认结果，它会出现在这里。")
        } actions: {
            if let startScan {
                Button("开始扫描", action: startScan)
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.cinnabar)
            }
        }
        .padding(CultureTheme.pagePadding)
    }

    private func historyCard(_ record: ScanHistoryRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(for: record))
                .font(.title2)
                .foregroundStyle(CultureTheme.antiqueGold)
                .frame(width: 54, height: 54)
                .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.canonicalName)
                        .font(.headline)
                        .foregroundStyle(CultureTheme.inkPrimary)
                    Spacer()
                    Text(record.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CultureTheme.cinnabar)
                }

                Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)

                Label(
                    locationText(for: record),
                    systemImage: record.place == nil ? "location.slash" : "location"
                )
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开历史扫描详情")
    }

    /// 坐标已记录但地名缺失时（如照片 EXIF 定位、逆地理编码失败）显示坐标兜底。
    private func locationText(for record: ScanHistoryRecord) -> String {
        if let placeName = record.placeName, !placeName.isEmpty {
            return placeName
        }
        if let latitude = record.latitude, let longitude = record.longitude {
            return String(localized: "已记录位置")
                + String(format: " %.3f, %.3f", latitude, longitude)
        }
        return String(localized: "未记录位置")
    }

    private func symbol(for record: ScanHistoryRecord) -> String {
        switch ObjectCategory(rawValue: record.categoryRawValue) {
        case .architecture: "building.columns"
        case .artifact: "seal"
        case .pattern: "camera.macro"
        case .exhibit: "photo.artframe"
        case .space: "square.3.layers.3d"
        case .other, nil: "sparkles"
        }
    }

    private func delete(_ record: ScanHistoryRecord) {
        let path = record.imageRelativePath
        modelContext.delete(record)
        try? modelContext.save()
        Task {
            try? await ScanMediaStore.shared.delete(relativePath: path)
        }
    }
}

#Preview {
    NavigationStack {
        ScanTimelineView()
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
