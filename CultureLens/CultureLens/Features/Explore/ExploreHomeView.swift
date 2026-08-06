import Foundation
import SwiftData
import SwiftUI

struct ExploreHomeView: View {
  private let contentService: CultureContentService

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
  private var historyRecords: [ScanHistoryRecord]
  @AppStorage("culturelens.seen-exploration-badges.v1")
  private var seenBadgeIDsValue = ""
  @State private var locationProvider = LocationContextProvider()
  @State private var recommendationState: RecommendationState = .loading
  @State private var reloadID = UUID()
  @State private var dailyOffset = 0
  @State private var placeName: String?
  @State private var celebratedBadge: ExplorationBadge?

  init(contentService: CultureContentService = .live()) {
    self.contentService = contentService
  }

  private var knowledgeStore: KnowledgeStore? {
    KnowledgeStore.shared
  }

  private var contactedIDs: Set<UUID> {
    Set(
      knowledgeProgressStore.entriesByID.values.compactMap { entry in
        entry.elementKey.flatMap(UUID.init(uuidString:)) ?? entry.nodeID
      }
    )
  }

  private var sortedElements: [KnowledgePack.Element] {
    (knowledgeStore?.elements ?? []).sorted { $0.sortKey < $1.sortKey }
  }

  /// Knowledge-pack nodes the user has already encountered. The quiz section
  /// receives concrete elements so it never asks the LLM about an unresolved
  /// legacy progress row.
  private var contactedElements: [KnowledgePack.Element] {
    guard let store = knowledgeStore else { return [] }
    return contactedIDs.compactMap { store.element(id: $0) }
      .sorted { ($0.sortKey, $0.id.uuidString) < ($1.sortKey, $1.id.uuidString) }
  }

  /// 每日确定性轮换：同一天所有用户看到同一元素，「换一个」只改本地 offset。
  private var dailyElement: KnowledgePack.Element? {
    let elements = sortedElements
    guard !elements.isEmpty else { return nil }
    let dayNumber = Int(Date().timeIntervalSince1970 / 86_400)
    return elements[(dayNumber + dailyOffset) % elements.count]
  }

  /// 已收集节点的图谱邻居中尚未收集的；图谱为空时回落到主题剩余节点。
  private var nextDiscoveries: [KnowledgePack.Element] {
    guard let store = knowledgeStore else { return [] }
    let contacted = contactedIDs
    var ids: [UUID] = []
    var seen = Set<UUID>()

    func append(_ id: UUID) {
      guard
        !contacted.contains(id),
        seen.insert(id).inserted,
        store.element(id: id) != nil
      else { return }
      ids.append(id)
    }

    for id in contacted.sorted(by: { $0.uuidString < $1.uuidString }) {
      for neighbor in store.relatedElements(forID: id, limit: 6) {
        append(neighbor.id)
      }
    }
    if ids.isEmpty {
      let themes = ThemeProgressCalculator.progressList(
        themes: store.pack.themes,
        contactedElementIds: contacted,
        knowledgeStore: store
      )
      for progress in themes {
        for id in progress.remainingIds {
          append(id)
        }
      }
    }
    return ids.prefix(3).compactMap { store.element(id: $0) }
  }

  private var collectedCount: Int {
    guard let store = knowledgeStore else { return 0 }
    return contactedIDs.filter { store.element(id: $0) != nil }.count
  }

  private var themeProgress: [ThemeProgress] {
    guard let store = knowledgeStore else { return [] }
    return ThemeProgressCalculator.progressList(
      themes: store.pack.themes,
      contactedElementIds: contactedIDs,
      knowledgeStore: store
    )
  }

  private var milestones: ExplorationMilestoneSnapshot {
    ExplorationMilestoneCalculator.snapshot(
      series: themeProgress,
      history: historyRecords.map(\.tripSnapshot),
      litNodeCount: collectedCount
    )
  }

  private var milestoneSignature: String {
    milestones.badges
      .filter(\.isUnlocked)
      .map(\.id)
      .joined(separator: "|")
  }

  /// 进行中的主题：未完成优先，按点亮比例降序，最多 3 个。
  private var activeThemes: [ThemeProgress] {
    return Array(
      themeProgress
        .filter { !$0.isComplete }
        .sorted {
          ($0.fractionComplete, $1.theme.sortKey) > ($1.fractionComplete, $0.theme.sortKey)
        }
        .prefix(3)
    )
  }

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.locale) private var locale

  private var isChineseLocale: Bool {
    locale.identifier.hasPrefix("zh")
  }

  var body: some View {
    // 用外层 GeometryReader 量视口（与 SplitDetailLayout 相同），不要量 ScrollView
    // 内容高度——内容永远更高，会把横屏也误判成单栏。
    GeometryReader { proxy in
      let isWideLayout =
        horizontalSizeClass == .regular
        && proxy.size.width > proxy.size.height

      ZStack {
        CulturePageBackground()

        ScrollView {
          VStack(alignment: .leading, spacing: 32) {
            masthead

            if isWideLayout {
              // 附近无内容时左栏很空，把封面故事挪到左栏平衡版面
              let nearbyHasItems = recommendationState.hasItems
              HStack(alignment: .top, spacing: 36) {
                VStack(alignment: .leading, spacing: 32) {
                  nearbySection
                  DidYouKnowQuizSection(elements: contactedElements)
                  if !nearbyHasItems {
                    dailySection(keepsColumnWidth: true)
                  }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 32) {
                  illuminationSection
                  collectionSection
                  if nearbyHasItems {
                    dailySection(keepsColumnWidth: true)
                  }
                  nextDiscoveriesSection
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
              }
            } else {
              // 竖屏单列：附近看点与问答在上，其余栏目依次向下。
              nearbySection
              DidYouKnowQuizSection(elements: contactedElements)
              illuminationSection
              collectionSection
              dailySection(keepsColumnWidth: false)
              nextDiscoveriesSection
            }

            MagazineFooterOrnament()
          }
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 28)
          .padding(.bottom, 40)
        }
      }
    }
    .cultureNavigationTitle("探索", showsBackButton: false)
    .task(id: reloadID) {
      await loadRecommendations()
    }
    .onAppear {
      presentNewBadgeIfNeeded()
    }
    .onChange(of: milestoneSignature) { _, _ in
      presentNewBadgeIfNeeded()
    }
    .sensoryFeedback(.success, trigger: celebratedBadge?.id)
    .overlay {
      if let celebratedBadge {
        BadgeCelebrationOverlay(
          badge: celebratedBadge,
          reduceMotion: reduceMotion
        ) {
          withAnimation(.easeOut(duration: 0.2)) {
            self.celebratedBadge = nil
          }
        }
        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.96)))
        .zIndex(10)
      }
    }
  }

  // MARK: - 刊头

  /// 杂志刊头：日期与所在城市 + 宋体大标题 + 粗细双线。不放品牌字标。
  private var masthead: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(mastheadDateline)
        .font(.caption)
        .tracking(0.5)
        .foregroundStyle(CultureTheme.inkSecondary)

      Text("探索")
        .font(CultureTypography.display(size: 40))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text("看看附近的现场，翻翻你的收集，每天再认识一个新的文化细节。")
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(3)

      VStack(spacing: 3) {
        Rectangle().fill(CultureTheme.inkPrimary).frame(height: 2)
        Rectangle().fill(CultureTheme.inkPrimary.opacity(0.35)).frame(height: 0.5)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// 期号（当年第几天）+ 农历日期（中文环境）+ 城市。
  private var mastheadDateline: String {
    let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: .now) ?? 1
    var parts = ["NO.\(dayOfYear)"]
    if isChineseLocale {
      parts.append(lunarDateString)
    } else {
      parts.append(Date.now.formatted(date: .long, time: .omitted))
    }
    if let placeName, !placeName.isEmpty {
      parts.append(placeName)
    }
    return parts.joined(separator: " · ")
  }

  /// 「丙午年六月廿四」式农历日期；ICU 对日中数码不本地化，日序手动转汉字。
  private var lunarDateString: String {
    let chinese = Calendar(identifier: .chinese)
    let formatter = DateFormatter()
    formatter.calendar = chinese
    formatter.locale = Locale(identifier: "zh_Hans_CN")
    formatter.dateFormat = "U年MMMM"
    let day = chinese.component(.day, from: .now)
    return formatter.string(from: .now) + Self.lunarDayNames[min(max(day, 1), 30) - 1]
  }

  private static let lunarDayNames = [
    "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
  ]

  @ViewBuilder
  private var nearbySection: some View {
    MagazineSectionHeader(eyebrow: "NEARBY", "附近看点", subtitle: "离你最近的文化现场，点开看详情")
    recommendationContent
  }

  @ViewBuilder
  private var collectionSection: some View {
    if knowledgeStore != nil {
      MagazineSectionHeader(eyebrow: "COLLECTION", "我的收集", subtitle: "已点亮的节点与进行中的主题")
      collectionContent
    }
  }

  @ViewBuilder
  private var illuminationSection: some View {
    if knowledgeStore != nil {
      MagazineSectionHeader(
        eyebrow: "ILLUMINATE",
        "点亮图鉴",
        subtitle: "让走过的城市与连成系的文化留下印记"
      )
      ExplorationIlluminationView(snapshot: milestones)
    }
  }

  @ViewBuilder
  private func dailySection(keepsColumnWidth: Bool) -> some View {
    if let daily = dailyElement {
      HStack(alignment: .firstTextBaseline) {
        MagazineSectionHeader(eyebrow: "COVER STORY", "封面故事", subtitle: "每天轮换一个文化细节")
        Spacer(minLength: 12)
        Button {
          dailyOffset += 1
        } label: {
          Label("换一个", systemImage: "shuffle")
            .font(.caption.weight(.semibold))
        }
        .tint(CultureTheme.cinnabar)
        .accessibilityIdentifier("explore.dailyShuffle")
      }

      CoverStoryFeature(
        element: daily,
        isCollected: contactedIDs.contains(daily.id),
        keepsColumnWidth: keepsColumnWidth
      )
    }
  }

  @ViewBuilder
  private var nextDiscoveriesSection: some View {
    if !nextDiscoveries.isEmpty {
      MagazineSectionHeader(eyebrow: "UP NEXT", "下一个看点", subtitle: "从你的图谱向外延伸")
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(nextDiscoveries.enumerated()), id: \.element.id) { index, element in
          if index > 0 { EditorialRule() }
          NavigationLink(value: AppRoute.knowledgeElement(element.id)) {
            NextDiscoveryRow(element: element)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  // MARK: - 附近看点

  @ViewBuilder
  private var recommendationContent: some View {
    switch recommendationState {
    case .loading:
      HStack(spacing: 12) {
        ProgressView()
        Text("正在读取附近的数据库内容…")
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)

    case .loaded(let recommendations):
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(recommendations.enumerated()), id: \.element.id) { index, recommendation in
          if index > 0 { EditorialRule() }
          let elementID =
            KnowledgeStore.shared?.resolveElementID(recommendation.culturalElement.key)
            ?? DeterministicID.culturalElement(recommendation.culturalElement.key)
          NavigationLink(value: AppRoute.knowledgeElement(elementID)) {
            NearbyEditorialRow(
              number: index + 1,
              recommendation: recommendation,
              isVisited: contactedIDs.contains(elementID)
            )
          }
          .buttonStyle(.plain)
        }
      }

    case .empty:
      recommendationNotice(
        title: "附近暂无已收录内容",
        message: String(localized: "你当前位置附近还没有收录的文化现场，到收录区域内再来看看。"),
        systemImage: "mappin.slash"
      )

    case .failed(let message):
      VStack(alignment: .leading, spacing: 12) {
        recommendationNotice(
          title: "无法读取附近内容",
          message: message,
          systemImage: "wifi.exclamationmark"
        )
        Button("重试") {
          reloadID = UUID()
        }
        .buttonStyle(.bordered)
        .tint(CultureTheme.cinnabar)
      }
    }
  }

  private func recommendationNotice(
    title: LocalizedStringKey,
    message: String,
    systemImage: String
  ) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: systemImage)
        .foregroundStyle(CultureTheme.cinnabar)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        Text(message)
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 8)
  }

  @MainActor
  private func loadRecommendations() async {
    guard !ProcessInfo.processInfo.arguments.contains("-UITesting") else {
      recommendationState = .empty
      return
    }

    recommendationState = .loading
    do {
      let place = try await locationProvider.requestBestPlace()
      placeName = place.displayName ?? place.cityName
      let response = try await contentService.nearbyRecommendations(
        place.latitude,
        place.longitude,
        50_000,
        6
      )
      recommendationState =
        response.introductions.isEmpty
        ? .empty
        : .loaded(response.introductions)
    } catch is CancellationError {
      return
    } catch {
      recommendationState = .failed(error.localizedDescription)
    }
  }

  private func presentNewBadgeIfNeeded() {
    guard celebratedBadge == nil else { return }
    guard !ProcessInfo.processInfo.arguments.contains("-UITesting") else { return }

    let seen = Set(seenBadgeIDsValue.split(separator: "|").map(String.init))
    let unlocked = milestones.badges.filter(\.isUnlocked)
    let unseen = unlocked.filter { !seen.contains($0.id) }
    guard let newest = unseen.last else { return }

    seenBadgeIDsValue = seen.union(unlocked.map(\.id)).sorted().joined(separator: "|")
    withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) {
      celebratedBadge = newest
    }
  }

  // MARK: - 我的收集

  /// 排版式统计：大数字 + 细线进度 + 分栏线主题行，不用盒子和系统进度条。
  private var collectionContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(collectedCount)")
          .font(CultureTypography.display(size: 44))
          .foregroundStyle(CultureTheme.inkPrimary)
        Text("/ \(sortedElements.count) 个节点")
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
        Spacer(minLength: 12)
        NavigationLink(value: AppRoute.themes) {
          Text("全部主题")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.cinnabar)
        }
        .accessibilityIdentifier("explore.themesLink")
      }

      ThinProgressRule(
        fraction: sortedElements.isEmpty
          ? 0
          : Double(collectedCount) / Double(sortedElements.count),
        tint: CultureTheme.cinnabar
      )
      .padding(.top, 10)
      .padding(.bottom, 14)

      if collectedCount == 0 {
        Text("还没有点亮任何节点。到扫描页拍下一个细节，或从下面的「封面故事」开始。")
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if activeThemes.isEmpty {
        Text("所有主题都已完成。")
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
      } else {
        ForEach(Array(activeThemes.enumerated()), id: \.element.theme.id) { index, progress in
          if index > 0 { EditorialRule() }
          NavigationLink(value: AppRoute.theme(progress.theme.sortKey)) {
            VStack(alignment: .leading, spacing: 8) {
              HStack(alignment: .firstTextBaseline) {
                Text(progress.theme.name)
                  .font(CultureTypography.title(.headline))
                  .foregroundStyle(CultureTheme.inkPrimary)
                  .lineLimit(1)
                Spacer(minLength: 8)
                Text(progress.statusText)
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(CultureTheme.inkSecondary)
              }
              ThinProgressRule(fraction: progress.fractionComplete, tint: CultureTheme.antiqueGold)
            }
            .padding(.vertical, 10)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .accessibilityIdentifier("explore.collectionCard")
  }
}

private enum RecommendationState {
  case loading
  case loaded([AttractionIntroductionRecommendation])
  case empty
  case failed(String)

  /// 只有真正拿到条目才视为有内容；加载中 / 空 / 失败都算左栏空旷。
  var hasItems: Bool {
    if case .loaded = self { return true }
    return false
  }
}

// MARK: - 点亮图鉴

private struct ExplorationIlluminationView: View {
  let snapshot: ExplorationMilestoneSnapshot

  @State private var selectedDetail: ExplorationIlluminationDetail?

  private let badgeColumns = [
    GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .top)
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      illuminationSummary

      if !snapshot.series.isEmpty {
        culturalSeries
      }

      illuminatedCities
      badgeShelf
    }
    .padding(20)
    .background {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
        .fill(CultureTheme.inkPrimary)
        .overlay(alignment: .topTrailing) {
          CelebrationSparkle()
            .stroke(CultureTheme.antiqueGold.opacity(0.1), lineWidth: 1)
            .frame(width: 112, height: 112)
            .offset(x: 22, y: -18)
            .accessibilityHidden(true)
        }
    }
    .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
    .accessibilityIdentifier("explore.illumination")
    .sheet(item: $selectedDetail) { detail in
      ExplorationIlluminationDetailSheet(detail: detail, snapshot: snapshot)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
  }

  private var illuminationSummary: some View {
    HStack(spacing: 0) {
      illuminationMetric(
        value: snapshot.completedSeriesCount,
        total: snapshot.series.count,
        label: "文化系"
      )
      summaryDivider
      illuminationMetric(value: snapshot.cities.count, total: nil, label: "城市")
      summaryDivider
      illuminationMetric(
        value: snapshot.unlockedBadgeCount,
        total: snapshot.badges.count,
        label: "徽章"
      )
    }
  }

  private var summaryDivider: some View {
    Rectangle()
      .fill(Color.white.opacity(0.14))
      .frame(width: 1, height: 42)
      .padding(.horizontal, 12)
  }

  private func illuminationMetric(value: Int, total: Int?, label: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text("\(value)")
          .font(CultureTypography.display(size: 30))
          .foregroundStyle(CultureTheme.antiqueGold)
          .contentTransition(.numericText())
        if let total {
          Text("/\(total)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.56))
        }
      }
      Text(label)
        .font(.caption)
        .foregroundStyle(Color.white.opacity(0.72))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var culturalSeries: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        illuminationLabel("文化系")
        Spacer()
        NavigationLink(value: AppRoute.themes) {
          Text("查看全部")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.antiqueGold)
        }
      }

      ScrollView(.horizontal) {
        HStack(spacing: 12) {
          ForEach(snapshot.series, id: \.theme.id) { progress in
            NavigationLink(value: AppRoute.theme(progress.theme.sortKey)) {
              CulturalSeriesSeal(progress: progress)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .scrollIndicators(.hidden)
    }
  }

  private var illuminatedCities: some View {
    VStack(alignment: .leading, spacing: 12) {
      illuminationLabel("点亮城市")

      if snapshot.cities.isEmpty {
        Text("带着镜头去现场，点亮你的第一座城市。")
          .font(.caption)
          .foregroundStyle(Color.white.opacity(0.68))
      } else {
        ScrollView(.horizontal) {
          HStack(spacing: 10) {
            ForEach(snapshot.cities) { city in
              Button {
                selectedDetail = .city(city)
              } label: {
                IlluminatedCityPill(city: city)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("已点亮城市 \(city.name)，\(city.scanCount) 次足迹")
              .accessibilityHint("查看城市足迹详情")
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  private var badgeShelf: some View {
    VStack(alignment: .leading, spacing: 12) {
      illuminationLabel("文化徽章")

      LazyVGrid(columns: badgeColumns, alignment: .leading, spacing: 16) {
        ForEach(snapshot.badges) { badge in
          Button {
            selectedDetail = .badge(badge)
          } label: {
            ExplorationBadgeMedallion(badge: badge)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            badge.isUnlocked
              ? "已获得徽章 \(badge.kind.title)，\(badge.kind.detail)"
              : "未获得徽章 \(badge.kind.title)，目标：\(badge.kind.detail)"
          )
          .accessibilityHint("查看徽章详情")
        }
      }
    }
  }

  private func illuminationLabel(_ title: LocalizedStringKey) -> some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .tracking(0.8)
      .foregroundStyle(Color.white.opacity(0.82))
  }
}

private struct CulturalSeriesSeal: View {
  let progress: ThemeProgress

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      ZStack {
        Circle()
          .stroke(Color.white.opacity(0.14), lineWidth: 2)
        Circle()
          .trim(from: 0, to: progress.fractionComplete)
          .stroke(
            progress.isComplete ? CultureTheme.antiqueGold : CultureTheme.cinnabar,
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
          )
          .rotationEffect(.degrees(-90))
        Image(ExplorationArtwork.seriesImageName(for: progress.theme))
          .resizable()
          .scaledToFill()
          .frame(width: 46, height: 46)
          .clipShape(Circle())
          .saturation(progress.isComplete ? 1 : 0.2)
          .opacity(progress.isComplete ? 1 : 0.72)
      }
      .frame(width: 54, height: 54)

      Text(progress.theme.name)
        .font(CultureTypography.body(.subheadline))
        .foregroundStyle(Color.white)
        .lineLimit(2)
        .frame(height: 38, alignment: .topLeading)

      Text(progress.isComplete ? "已点亮" : "\(progress.contactedCount)/\(progress.requiredCount)")
        .font(.caption2.monospacedDigit().weight(.semibold))
        .foregroundStyle(
          progress.isComplete ? CultureTheme.antiqueGold : Color.white.opacity(0.56)
        )
    }
    .frame(width: 112, alignment: .leading)
    .padding(13)
    .background(Color.white.opacity(progress.isComplete ? 0.12 : 0.06))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(
          progress.isComplete
            ? CultureTheme.antiqueGold.opacity(0.45)
            : Color.white.opacity(0.08),
          lineWidth: 1
        )
    }
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      progress.isComplete
        ? "文化系 \(progress.theme.name) 已点亮"
        : "文化系 \(progress.theme.name)，已点亮 \(progress.contactedCount) / \(progress.requiredCount)"
    )
  }
}

private struct ExplorationBadgeMedallion: View {
  let badge: ExplorationBadge

  var body: some View {
    VStack(spacing: 7) {
      ZStack {
        Circle()
          .fill(
            badge.isUnlocked
              ? CultureTheme.antiqueGold.opacity(0.16)
              : Color.white.opacity(0.045)
          )
        Circle()
          .strokeBorder(
            badge.isUnlocked
              ? CultureTheme.antiqueGold.opacity(0.72)
              : Color.white.opacity(0.12),
            lineWidth: 1
          )
        Image(ExplorationArtwork.badgeImageName(for: badge.kind))
          .resizable()
          .scaledToFill()
          .frame(width: 46, height: 46)
          .clipShape(Circle())
          .saturation(badge.isUnlocked ? 1 : 0)
          .opacity(badge.isUnlocked ? 1 : 0.28)
      }
      .frame(width: 52, height: 52)
      .shadow(
        color: badge.isUnlocked ? CultureTheme.antiqueGold.opacity(0.18) : .clear,
        radius: 9
      )

      Text(badge.kind.title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(badge.isUnlocked ? Color.white : Color.white.opacity(0.32))
        .multilineTextAlignment(.center)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .top)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      badge.isUnlocked
        ? "已获得徽章 \(badge.kind.title)，\(badge.kind.detail)"
        : "未获得徽章 \(badge.kind.title)，目标：\(badge.kind.detail)"
    )
  }
}

private struct BadgeCelebrationOverlay: View {
  let badge: ExplorationBadge
  let reduceMotion: Bool
  let onDismiss: () -> Void

  @State private var revealed = false

  var body: some View {
    ZStack {
      Color.black.opacity(0.5)
        .ignoresSafeArea()

      celebrationParticles

      VStack(spacing: 18) {
        Text("NEW BADGE")
          .font(.caption.weight(.bold))
          .tracking(2.4)
          .foregroundStyle(CultureTheme.cinnabar)

        ZStack {
          Circle()
            .fill(CultureTheme.antiqueGold.opacity(0.13))
            .frame(width: 146, height: 146)
            .blur(radius: revealed ? 0 : 10)

          Circle()
            .strokeBorder(CultureTheme.antiqueGold, lineWidth: 2)
            .frame(width: 112, height: 112)

          Circle()
            .strokeBorder(CultureTheme.antiqueGold.opacity(0.45), lineWidth: 1)
            .frame(width: 96, height: 96)

          Image(ExplorationArtwork.badgeImageName(for: badge.kind))
            .resizable()
            .scaledToFill()
            .frame(width: 96, height: 96)
            .clipShape(Circle())
        }
        .scaleEffect(reduceMotion || revealed ? 1 : 0.72)
        .rotationEffect(.degrees(reduceMotion || revealed ? 0 : -8))

        VStack(spacing: 8) {
          Text("获得新徽章")
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
          Text(badge.kind.title)
            .font(CultureTypography.display(size: 30))
            .foregroundStyle(CultureTheme.inkPrimary)
          Text(badge.kind.detail)
            .font(CultureTypography.body(.subheadline))
            .foregroundStyle(CultureTheme.inkSecondary)
            .multilineTextAlignment(.center)
        }

        Button("收下徽章", action: onDismiss)
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.cinnabar)
          .controlSize(.large)
          .accessibilityIdentifier("explore.badgeCelebrationDismiss")
      }
      .padding(.horizontal, 28)
      .padding(.vertical, 32)
      .frame(maxWidth: 340)
      .background(CultureTheme.canvas, in: RoundedRectangle(cornerRadius: 28))
      .overlay {
        RoundedRectangle(cornerRadius: 28)
          .stroke(CultureTheme.antiqueGold.opacity(0.42), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.25), radius: 32, y: 18)
      .padding(24)
    }
    .accessibilityAddTraits(.isModal)
    .onAppear {
      guard !reduceMotion else {
        revealed = true
        return
      }
      withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
        revealed = true
      }
    }
  }

  private var celebrationParticles: some View {
    GeometryReader { proxy in
      ForEach(0..<12, id: \.self) { index in
        let angle = Double(index) / 12 * Double.pi * 2
        let radius = min(proxy.size.width, proxy.size.height) * 0.34
        let color = index.isMultiple(of: 2) ? CultureTheme.antiqueGold : CultureTheme.cinnabar
        Group {
          if index.isMultiple(of: 3) {
            CelebrationSparkle()
              .fill(color)
              .frame(width: 12, height: 12)
          } else {
            Circle()
              .fill(color)
              .frame(width: 5, height: 5)
          }
        }
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
          .offset(
            x: revealed && !reduceMotion ? CGFloat(cos(angle)) * radius : 0,
            y: revealed && !reduceMotion ? CGFloat(sin(angle)) * radius : 0
          )
          .opacity(revealed ? 0.9 : 0)
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct CelebrationSparkle: Shape {
  func path(in rect: CGRect) -> Path {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let points = [
      CGPoint(x: center.x, y: rect.minY),
      CGPoint(x: center.x + rect.width * 0.16, y: center.y - rect.height * 0.16),
      CGPoint(x: rect.maxX, y: center.y),
      CGPoint(x: center.x + rect.width * 0.16, y: center.y + rect.height * 0.16),
      CGPoint(x: center.x, y: rect.maxY),
      CGPoint(x: center.x - rect.width * 0.16, y: center.y + rect.height * 0.16),
      CGPoint(x: rect.minX, y: center.y),
      CGPoint(x: center.x - rect.width * 0.16, y: center.y - rect.height * 0.16),
    ]
    var path = Path()
    path.addLines(points)
    path.closeSubpath()
    return path
  }
}

// MARK: - 附近看点条目

/// 编辑式条目：大号编号 + 宋体标题 + 元信息 + 摘要，行间细线分隔，无卡片。
private struct NearbyEditorialRow: View {
  let number: Int
  let recommendation: AttractionIntroductionRecommendation
  var isVisited: Bool = false

  private var thumbnailURL: URL? {
    recommendation.introduction.imageBlocks.first?.imageURL
  }

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      // 目录式大号编号
      Text(String(format: "%02d", number))
        .font(CultureTypography.display(size: 26))
        .foregroundStyle(CultureTheme.inkPrimary.opacity(0.32))
        .frame(width: 38, alignment: .leading)
        .padding(.top, 16)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 14) {
          VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
              Text(recommendation.name)
                .font(CultureTypography.title(.title3))
                .foregroundStyle(CultureTheme.inkPrimary)
              Spacer(minLength: 12)
              if isVisited {
                SealBadge(character: "访", size: 22)
                  .accessibilityLabel("已到访")
              }
              Text(distanceText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(CultureTheme.cinnabar)
            }

            Text("\(recommendation.attraction.name) · \(recommendation.culturalElement.name)")
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }

          if let thumbnailURL {
            CachedAsyncImage(url: thumbnailURL) { phase in
              if case .success(let image) = phase {
                image
                  .resizable()
                  .scaledToFill()
                  .magazinePhoto()
              }
            }
            .frame(width: 88, height: 66)
            .clipped()
          }
        }

        Text(recommendation.introduction.plainText)
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineSpacing(3)
          .lineLimit(3)
      }
    }
    .padding(.vertical, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var distanceText: LocalizedStringKey {
    if recommendation.distanceMeters < 1_000 {
      return "\(Int(recommendation.distanceMeters.rounded())) 米"
    }
    let kilometers = String(format: "%.1f", recommendation.distanceMeters / 1_000)
    return "\(kilometers) 公里"
  }
}

// MARK: - 封面故事

/// 墨版封面故事：墨底反白与整页纸面形成强对比。
/// 无图且中文环境下标题竖排（中式编辑排版）；知识包图片到位后切换大图版式。
private struct CoverStoryFeature: View {
  let element: KnowledgePack.Element
  let isCollected: Bool
  /// 双栏布局时保持栏宽；单列（含 iPad 竖屏）整块出血到屏幕边缘。
  var keepsColumnWidth: Bool = false

  @Environment(\.locale) private var locale

  private var isChineseLocale: Bool {
    locale.identifier.hasPrefix("zh")
  }

  private var coverImageURL: URL? {
    element.introduction.imageBlocks.first?.imageURL
  }

  var body: some View {
    NavigationLink(value: AppRoute.knowledgeElement(element.id)) {
      VStack(alignment: .leading, spacing: 0) {
        if let coverImageURL {
          coverPhoto(coverImageURL)
        }

        ZStack(alignment: .topTrailing) {
          if coverImageURL != nil {
            // 有图时以金色首字水印衬底
            Text(String(element.name.prefix(1)))
              .font(CultureTypography.display(size: 150))
              .foregroundStyle(CultureTheme.antiqueGold.opacity(0.14))
              .offset(x: 12, y: -32)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }

          if coverImageURL == nil, isChineseLocale {
            // 无图：导语在左，标题竖排在右
            HStack(alignment: .top, spacing: 20) {
              VStack(alignment: .leading, spacing: 12) {
                collectedMeta
                fragmentText
              }
              .frame(maxWidth: .infinity, alignment: .leading)

              verticalTitle
            }
          } else {
            VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .firstTextBaseline) {
                LocalizedPackText(
                  source: element.name,
                  cacheNamespace: "element",
                  cacheKey: element.key
                )
                .font(CultureTypography.display(size: 30))
                .foregroundStyle(CultureTheme.canvas)

                Spacer(minLength: 12)

                collectedMeta
              }

              fragmentText
            }
          }
        }
        .padding(22)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(CultureTheme.inkPrimary)
      .clipped()
      // 单列时整块墨版出血到屏幕边缘；双栏里保持栏宽
      .padding(
        .horizontal,
        keepsColumnWidth ? 0 : -CultureTheme.pagePadding
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("explore.dailyCard")
  }

  private func coverPhoto(_ url: URL) -> some View {
    CachedAsyncImage(
      url: url,
      transaction: Transaction(animation: .easeOut(duration: 0.3))
    ) { phase in
      switch phase {
      case .success(let image):
        image
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity)
          .frame(height: 240)
          .clipped()
          .magazinePhoto()
          .transition(.opacity)
      case .failure:
        EmptyView()
      case .empty:
        Rectangle()
          .fill(Color.white.opacity(0.08))
          .frame(maxWidth: .infinity)
          .frame(height: 240)
      @unknown default:
        EmptyView()
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// 竖排标题：逐字纵排，自上至下。
  private var verticalTitle: some View {
    VStack(spacing: 0) {
      ForEach(Array(element.name.enumerated()), id: \.offset) { _, character in
        Text(String(character))
          .font(CultureTypography.display(size: 28))
          .foregroundStyle(CultureTheme.canvas)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(element.name)
  }

  private var collectedMeta: some View {
    HStack(spacing: 8) {
      if isCollected {
        SealBadge(character: "藏", size: 24)
      }
      Text(isCollected ? "已收集" : "未收集")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.canvas.opacity(isCollected ? 0.6 : 0.45))
    }
    .accessibilityElement(children: .combine)
  }

  private var fragmentText: some View {
    LocalizedPackText(
      source: element.introduction.plainText,
      cacheNamespace: "element",
      cacheKey: element.key,
      kind: .fragment
    )
    .font(CultureTypography.body(.subheadline))
    .foregroundStyle(CultureTheme.canvas.opacity(0.72))
    .lineSpacing(4)
    .lineLimit(4)
  }
}

// MARK: - 下一个看点条目

private struct NextDiscoveryRow: View {
  let element: KnowledgePack.Element

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        LocalizedPackText(
          source: element.name,
          cacheNamespace: "element",
          cacheKey: element.key
        )
        .font(CultureTypography.title(.headline))
        .foregroundStyle(CultureTheme.inkPrimary)

        LocalizedPackText(
          source: element.introduction.plainText,
          cacheNamespace: "element",
          cacheKey: element.key,
          kind: .fragment
        )
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(2)
      }

      Spacer(minLength: 8)

      Image(systemName: "arrow.right")
        .font(.subheadline.weight(.light))
        .foregroundStyle(CultureTheme.cinnabar)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 14)
    .contentShape(Rectangle())
  }
}

#Preview {
  NavigationStack {
    ExploreHomeView(
      contentService: CultureContentService { _, _, _, _ in
        NearbyRecommendationsResponse(
          requestedLocation: RequestedRecommendationLocation(
            latitude: 30.25,
            longitude: 120.15,
            radiusMeters: 50_000
          ),
          totalMatches: 1,
          introductions: [
            AttractionIntroductionRecommendation(
              key: "wenlan-pavilion.imperial-library",
              name: "文澜阁的藏书楼身份",
              introduction: RichTextDocument(
                schemaVersion: 1,
                blocks: [
                  .init(type: "paragraph", text: "把国家编纂工程落实为具体的收藏、保管与阅读空间。")
                ]
              ),
              culturalElement: .init(
                key: "siku-quanshu-library",
                name: "《四库全书》与皇家藏书楼"
              ),
              attraction: .init(key: "wenlan-pavilion", name: "文澜阁"),
              location: .init(latitude: 30.25, longitude: 120.14),
              distanceMeters: 1_147.2
            )
          ]
        )
      }
    )
  }
  .environment(KnowledgeProgressStore())
}
