import SwiftData
import SwiftUI

/// Review hub: timeline and visit-trip previews side by side (iPad) or stacked (iPhone).
struct ReviewHomeView: View {
    var showsBackButton: Bool = true
    var startScan: (() -> Void)?

    private static let previewLimit = 10

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    private var trips: [VisitTrip] {
        VisitTripBuilder.cluster(records.map(\.tripSnapshot))
    }

    private var previewRecords: [ScanHistoryRecord] {
        Array(records.prefix(Self.previewLimit))
    }

    private var previewTrips: [VisitTrip] {
        Array(trips.prefix(Self.previewLimit))
    }

    private var usesSideBySideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            Group {
                if usesSideBySideLayout {
                    sideBySideLayout
                } else {
                    stackedLayout
                }
            }
        }
        .cultureNavigationTitle("回顾", showsBackButton: showsBackButton)
    }

    private var stackedLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                timelineSection
                tripsSection
            }
            .padding(.horizontal, CultureTheme.pagePadding)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    private var sideBySideLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                timelineSection
                    .padding(.horizontal, CultureTheme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(CultureTheme.hairline)
                .frame(width: 1)
                .padding(.vertical, 16)

            ScrollView {
                tripsSection
                    .padding(.horizontal, CultureTheme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MagazineSectionHeader(
                eyebrow: "TIMELINE",
                "时间线足迹",
                subtitle: "按时间回看每一次扫描。"
            )

            if previewRecords.isEmpty {
                compactEmptyState(
                    title: "还没有扫描足迹",
                    systemImage: "clock.arrow.circlepath",
                    message: "完成一次扫描并确认结果，它会出现在这里。",
                    actionTitle: startScan == nil ? nil : "开始扫描",
                    action: startScan
                )
            } else {
                ForEach(Array(previewRecords.enumerated()), id: \.element.recordID) { index, record in
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

                if !records.isEmpty {
                    moreButton(route: .scanTimeline, accessibilityHint: "查看全部时间线足迹")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MagazineSectionHeader(
                eyebrow: "JOURNAL",
                "文化回顾",
                subtitle: "相近时间与地点的识别收成参观汇总。"
            )

            if previewTrips.isEmpty {
                compactEmptyState(
                    title: "还没有文化回顾",
                    systemImage: "book.closed",
                    message: "完成一次扫描并保存后，相近时间与地点的识别会聚成一次参观回顾。"
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(previewTrips.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { EditorialRule() }
                        NavigationLink(value: AppRoute.visitTrip(trip.id)) {
                            VisitTripRow(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                    EditorialRule()
                }

                if !trips.isEmpty {
                    moreButton(route: .visitTripList, accessibilityHint: "查看全部文化回顾")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func moreButton(route: AppRoute, accessibilityHint: LocalizedStringKey) -> some View {
        NavigationLink(value: route) {
            HStack {
                Text("更多")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(CultureTheme.cinnabar)
            .padding(.vertical, CultureTheme.rowPadding)
            .overlay(alignment: .bottom) { EditorialRule() }
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    private func compactEmptyState(
        title: LocalizedStringKey,
        systemImage: String,
        message: LocalizedStringKey,
        actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.inkPrimary)
            Text(message)
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(CultureTheme.cinnabar)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, CultureTheme.rowPadding)
        .overlay(alignment: .top) { EditorialRule() }
        .overlay(alignment: .bottom) { EditorialRule() }
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
        ReviewHomeView(showsBackButton: false)
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
