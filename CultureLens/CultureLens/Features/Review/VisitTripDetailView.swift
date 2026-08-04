import SwiftData
import SwiftUI

struct VisitTripDetailView: View {
  let tripID: UUID

  @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
  private var records: [ScanHistoryRecord]

  private var trip: VisitTrip? {
    VisitTripBuilder.cluster(records.map(\.tripSnapshot))
      .first { $0.id == tripID }
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if let trip {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 24) {
            summaryHeader(trip)
            statsRow(trip)

            if !trip.attractionNames.isEmpty {
              sectionTitle("走过的景点")
              Text(trip.attractionNames.joined(separator: " · "))
                .font(.body)
                .foregroundStyle(CultureTheme.inkSecondary)
            }

            if !trip.objects.isEmpty {
              sectionTitle("文化卡片")
              Text("本次点亮的对象，可直接分享。")
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)

              ForEach(trip.objects) { object in
                VStack(alignment: .leading, spacing: 10) {
                  NavigationLink(value: AppRoute.object(object.id)) {
                    CultureObjectCard(object: object, showsBrandMark: true)
                  }
                  .buttonStyle(.plain)

                  ShareCultureCardButton(object: object, label: .titled)
                    .buttonStyle(.bordered)
                    .tint(CultureTheme.inkPrimary)
                }
              }
            }

            sectionTitle("识别记录")
            ForEach(trip.recordIDs, id: \.self) { recordID in
              if let record = records.first(where: { $0.recordID == recordID }) {
                NavigationLink(value: AppRoute.history(recordID)) {
                  HStack {
                    VStack(alignment: .leading, spacing: 4) {
                      Text(record.canonicalName)
                        .font(.headline)
                        .foregroundStyle(CultureTheme.inkPrimary)
                      Text(
                        record.createdAt,
                        format: .dateTime.hour().minute()
                      )
                      .font(.caption)
                      .foregroundStyle(CultureTheme.inkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  .padding(14)
                  .background(
                    CultureTheme.surface,
                    in: RoundedRectangle(cornerRadius: 16)
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 20)
          .padding(.bottom, 40)
        }
      } else {
        ContentUnavailableView("找不到这次参观", systemImage: "book.closed")
      }
    }
    .cultureNavigationTitle(trip?.title ?? "文化回顾")
  }

  private func summaryHeader(_ trip: VisitTrip) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(trip.durationText)
        .font(.caption)
        .foregroundStyle(CultureTheme.cinnabar)

      Text(trip.title)
        .font(.cultureSerif(.largeTitle))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text("一次参观里，识别被聚合成可回看的文化路径。")
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
  }

  private func statsRow(_ trip: VisitTrip) -> some View {
    HStack(spacing: 0) {
      statCell(value: "\(trip.litNodeCount)", label: "点亮节点")
      Divider().frame(height: 36)
      statCell(value: "\(trip.attractionNames.count)", label: "走过景点")
      Divider().frame(height: 36)
      statCell(value: "\(trip.newRelationCount)", label: "新增关系")
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  private func statCell(value: String, label: String) -> some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title2.monospacedDigit().weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(label)
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.cultureSerif(.title2))
      .foregroundStyle(CultureTheme.inkPrimary)
  }
}

#Preview {
  NavigationStack {
    VisitTripDetailView(tripID: UUID())
  }
  .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
