import SwiftData
import SwiftUI

struct VisitTripDetailView: View {
  let tripID: UUID

  @Environment(AppLanguageStore.self) private var languageStore
  @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
  private var records: [ScanHistoryRecord]

  @State private var journalBlurb: String?

  private var trip: VisitTrip? {
    VisitTripBuilder.cluster(records.map(\.tripSnapshot))
      .first { $0.id == tripID }
  }

  private var journalLoadID: String {
    guard let trip else { return "empty|\(languageStore.language.rawValue)" }
    let objectDigest = trip.objects.map(\.canonicalName).joined(separator: "|")
    return "\(trip.id.uuidString)|\(languageStore.language.rawValue)|\(trip.scanCount)|\(objectDigest)"
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      if let trip {
        SplitDetailLayout(topPadding: 16, bottomPadding: 40) { isWide in
          leadingColumn(trip, isWide: isWide)
        } trailing: { isWide in
          trailingColumn(trip, isWide: isWide)
        }
      } else {
        ContentUnavailableView("找不到这次参观", systemImage: "book.closed")
      }
    }
    .cultureNavigationTitle(trip.map { LocalizedStringKey($0.title) } ?? "文化回顾")
    .toolbar {
      if let trip {
        ToolbarItem(placement: .topBarTrailing) {
          ShareVisitTripButton(trip: trip, label: .icon)
        }
      }
    }
    .task(id: journalLoadID) {
      guard let trip else {
        journalBlurb = nil
        return
      }
      await loadJournalBlurb(for: trip)
    }
  }

  @ViewBuilder
  private func leadingColumn(_ trip: VisitTrip, isWide: Bool) -> some View {
    // Bleed hero to screen edges on phone / portrait; keep column width on iPad landscape.
    VisitTripHeroView(trip: trip, height: isWide ? 360 : 240)
      .clipShape(RoundedRectangle(cornerRadius: isWide ? 20 : 0, style: .continuous))
      .padding(.horizontal, isWide ? 0 : -CultureTheme.pagePadding)

    summaryHeader(trip, showTitle: true)

    statsRow(trip)

    ShareVisitTripButton(trip: trip, label: .titled)
      .buttonStyle(.bordered)
      .tint(CultureTheme.inkPrimary)

    if isWide, !trip.attractionNames.isEmpty {
      attractionsSection(trip)
    }
  }

  @ViewBuilder
  private func trailingColumn(_ trip: VisitTrip, isWide: Bool) -> some View {
    if !isWide, !trip.attractionNames.isEmpty {
      attractionsSection(trip)
    }

    if !trip.objects.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        MagazineSectionHeader(
          eyebrow: "CARDS",
          "文化卡片",
          subtitle: "本次点亮的对象，可直接分享。"
        )

        let columns = isWide
          ? [GridItem(.adaptive(minimum: 220), spacing: 16)]
          : [GridItem(.flexible())]

        LazyVGrid(columns: columns, spacing: 16) {
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
      }
    }

    VStack(alignment: .leading, spacing: 0) {
      MagazineSectionHeader(eyebrow: "SCANS", "识别记录")
        .padding(.bottom, 4)

      ForEach(Array(trip.recordIDs.enumerated()), id: \.element) { index, recordID in
        if let record = records.first(where: { $0.recordID == recordID }) {
          if index > 0 { EditorialRule() }
          NavigationLink(value: AppRoute.history(recordID)) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(record.canonicalName)
                  .font(CultureTypography.title(.headline))
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
                .foregroundStyle(CultureTheme.inkSecondary.opacity(0.7))
            }
            .padding(.vertical, CultureTheme.rowPadding)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      EditorialRule()
    }

    MagazineFooterOrnament()
  }

  private func attractionsSection(_ trip: VisitTrip) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      MagazineSectionHeader(eyebrow: "SITES", "走过的景点")
      Text(trip.attractionNames.joined(separator: " · "))
        .font(CultureTypography.body(.body))
        .foregroundStyle(CultureTheme.inkSecondary)
    }
  }

  private func summaryHeader(_ trip: VisitTrip, showTitle: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(verbatim: "JOURNAL")
        .font(CultureTypography.eyebrow(.caption))
        .tracking(2)
        .foregroundStyle(CultureTheme.cinnabar)

      Text(trip.durationText)
        .font(.caption)
        .foregroundStyle(CultureTheme.cinnabar)

      if showTitle {
        Text(trip.title)
          .font(CultureTypography.title(.largeTitle))
          .foregroundStyle(CultureTheme.inkPrimary)
      }

      Text(journalBlurb ?? placeholderBlurb)
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(journalBlurb ?? String(localized: "正在撰写回顾介绍"))

      MagazineDoubleRule()
        .padding(.top, 4)
    }
  }

  private var placeholderBlurb: String {
    String(localized: "一次参观里，识别被聚合成可回看的文化路径。")
  }

  @MainActor
  private func loadJournalBlurb(for trip: VisitTrip) async {
    let language = languageStore.language
    // Instant concrete copy while the editorial blurb loads / reuses cache.
    journalBlurb = VisitTripShareCopyService.fallbackCopy(for: trip, language: language).blurb
    do {
      let copy = try await VisitTripShareCopyService.shared.copy(for: trip, language: language)
      journalBlurb = copy.blurb
    } catch {
      journalBlurb = VisitTripShareCopyService.fallbackCopy(for: trip, language: language).blurb
    }
  }

  private func statsRow(_ trip: VisitTrip) -> some View {
    HStack(spacing: 0) {
      statCell(value: "\(trip.litNodeCount)", label: "点亮节点")
      Rectangle()
        .fill(CultureTheme.hairline)
        .frame(width: 1, height: 36)
      statCell(value: "\(trip.attractionNames.count)", label: "走过景点")
      Rectangle()
        .fill(CultureTheme.hairline)
        .frame(width: 1, height: 36)
      statCell(value: "\(trip.newRelationCount)", label: "新增关系")
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .overlay(alignment: .top) { EditorialRule() }
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private func statCell(value: String, label: LocalizedStringKey) -> some View {
    VStack(spacing: 4) {
      Text(value)
        .font(CultureTypography.display(size: 28))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(label)
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .frame(maxWidth: .infinity)
  }
}

#Preview {
  NavigationStack {
    VisitTripDetailView(tripID: UUID())
  }
  .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
  .environment(AppLanguageStore())
  .environment(ImageGenerationPreferenceStore())
}
