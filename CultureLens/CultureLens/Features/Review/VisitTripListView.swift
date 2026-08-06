import SwiftData
import SwiftUI

struct VisitTripListView: View {
    var showsBackButton: Bool = true

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    private var trips: [VisitTrip] {
        VisitTripBuilder.cluster(records.map(\.tripSnapshot))
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            if trips.isEmpty {
                ContentUnavailableView {
                    Label("还没有文化回顾", systemImage: "book.closed")
                } description: {
                    Text("完成一次扫描并保存后，相近时间与地点的识别会聚成一次参观回顾。")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
                        MagazinePageHeader(
                            eyebrow: "JOURNAL",
                            title: "文化回顾",
                            message: "把一次参观里点亮的节点、走过的景点与新认识的关系收成可回看的行程。"
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                                if index > 0 { EditorialRule() }
                                NavigationLink(value: AppRoute.visitTrip(trip.id)) {
                                    VisitTripRow(trip: trip)
                                }
                                .buttonStyle(.plain)
                            }
                            EditorialRule()
                        }

                        MagazineFooterOrnament()
                    }
                    .padding(.horizontal, CultureTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        .cultureNavigationTitle("文化回顾", showsBackButton: showsBackButton)
    }
}

struct VisitTripRow: View {
    let trip: VisitTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(trip.title)
                    .font(CultureTypography.title(.title3))
                    .foregroundStyle(CultureTheme.inkPrimary)
                Spacer()
                Text("\(trip.scanCount) 次识别")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CultureTheme.cinnabar)
            }

            Text(trip.durationText)
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)

            HStack(spacing: 16) {
                Label("\(trip.litNodeCount) 节点", systemImage: "sparkles")
                Label("\(trip.attractionNames.count) 景点", systemImage: "mappin.and.ellipse")
                Label("\(trip.newRelationCount) 关系", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
        }
        .padding(.vertical, CultureTheme.rowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开本次参观回顾")
    }
}

#Preview {
    NavigationStack {
        VisitTripListView()
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
