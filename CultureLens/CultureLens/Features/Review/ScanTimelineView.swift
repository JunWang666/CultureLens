import SwiftData
import SwiftUI

/// Chronological scan footprint list.
struct ScanTimelineView: View {
    var showsBackButton: Bool = true
    var startScan: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    var body: some View {
        ZStack {
            CulturePageBackground()

            if records.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.recordID) { index, record in
                            NavigationLink(value: AppRoute.history(record.recordID)) {
                                ScanHistoryTimelineRow(
                                    record: record,
                                    showsTopRule: index == 0
                                )
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
            }
        }
        .cultureNavigationTitle("时间线足迹", showsBackButton: showsBackButton)
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

    private func delete(_ record: ScanHistoryRecord) {
        let path = record.imageRelativePath
        modelContext.delete(record)
        try? modelContext.save()
        Task {
            try? await ScanMediaStore.shared.delete(relativePath: path)
        }
    }
}

struct ScanHistoryTimelineRow: View {
    let record: ScanHistoryRecord
    /// 列表首行是否画顶线；连续条目只画底线避免双线。
    var showsTopRule: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTopRule { EditorialRule() }
            HStack(alignment: .top, spacing: 14) {
                Text(record.createdAt, format: .dateTime.day().month())
                    .font(.magazineDisplay(size: 22))
                    .foregroundStyle(CultureTheme.inkPrimary.opacity(0.32))
                    .frame(width: 44, alignment: .leading)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(record.canonicalName)
                            .font(.magazineDisplay(.headline))
                            .foregroundStyle(CultureTheme.inkPrimary)
                        Spacer(minLength: 8)
                        Text(record.confidence, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(CultureTheme.cinnabar)
                    }

                    Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(CultureTheme.inkSecondary)

                    Label(
                        locationText,
                        systemImage: record.place == nil ? "location.slash" : "location"
                    )
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary.opacity(0.7))
                    .padding(.top, 4)
            }
            .padding(.vertical, CultureTheme.rowPadding)
            EditorialRule()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开历史扫描详情")
    }

    /// 坐标已记录但地名缺失时（如照片 EXIF 定位、逆地理编码失败）显示坐标兜底。
    private var locationText: String {
        if let placeName = record.placeName, !placeName.isEmpty {
            return placeName
        }
        if let latitude = record.latitude, let longitude = record.longitude {
            return String(localized: "已记录位置")
                + String(format: " %.3f, %.3f", latitude, longitude)
        }
        return String(localized: "未记录位置")
    }
}

#Preview {
    NavigationStack {
        ScanTimelineView()
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
