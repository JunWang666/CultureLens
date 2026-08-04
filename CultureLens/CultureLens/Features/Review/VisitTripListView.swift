import SwiftData
import SwiftUI

struct VisitTripListView: View {
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
          LazyVStack(alignment: .leading, spacing: 16) {
            EditorialHeader(
              eyebrow: nil,
              title: "文化回顾",
              message: "把一次参观里点亮的节点、走过的景点与新认识的关系收成可回看的行程。"
            )

            ForEach(trips) { trip in
              NavigationLink(value: AppRoute.visitTrip(trip.id)) {
                tripRow(trip)
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 20)
          .padding(.bottom, 40)
        }
      }
    }
    .cultureNavigationTitle("文化回顾")
  }

  private func tripRow(_ trip: VisitTrip) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(trip.title)
          .font(.cultureSerif(.title3))
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
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
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
