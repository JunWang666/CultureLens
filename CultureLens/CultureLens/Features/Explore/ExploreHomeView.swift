import Foundation
import SwiftUI

struct ExploreHomeView: View {
  private let contentService: CultureContentService

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @State private var locationProvider = LocationContextProvider()
  @State private var recommendationState: RecommendationState = .loading
  @State private var reloadID = UUID()
  @State private var dailyOffset = 0

  init(contentService: CultureContentService = .live()) {
    self.contentService = contentService
  }

  private var knowledgeStore: KnowledgeStore? {
    KnowledgeStore.shared
  }

  private var contactedKeys: Set<String> {
    Set(knowledgeProgressStore.entriesByID.values.compactMap(\.elementKey))
  }

  private var sortedElements: [KnowledgePack.Element] {
    (knowledgeStore?.elements ?? []).sorted { $0.key < $1.key }
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
    let contacted = contactedKeys
    var keys: [String] = []
    var seen = Set<String>()

    func append(_ key: String) {
      guard
        !contacted.contains(key),
        seen.insert(key).inserted,
        store.element(key: key) != nil
      else { return }
      keys.append(key)
    }

    for key in contacted.sorted() {
      for neighbor in store.relatedElements(forKey: key, limit: 6) {
        append(neighbor.key)
      }
    }
    if keys.isEmpty {
      let themes = ThemeProgressCalculator.progressList(
        themes: store.pack.themes,
        contactedElementKeys: contacted,
        knowledgeStore: store
      )
      for progress in themes {
        for key in progress.remainingKeys {
          append(key)
        }
      }
    }
    return keys.prefix(3).compactMap { store.element(key: $0) }
  }

  private var collectedCount: Int {
    guard let store = knowledgeStore else { return 0 }
    return contactedKeys.filter { store.element(key: $0) != nil }.count
  }

  /// 进行中的主题：未完成优先，按点亮比例降序，最多 3 个。
  private var activeThemes: [ThemeProgress] {
    guard let store = knowledgeStore else { return [] }
    return Array(
      ThemeProgressCalculator.progressList(
        themes: store.pack.themes,
        contactedElementKeys: contactedKeys,
        knowledgeStore: store
      )
      .filter { !$0.isComplete }
      .sorted { ($0.fractionComplete, $1.theme.key) > ($1.fractionComplete, $0.theme.key) }
      .prefix(3)
    )
  }

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// iPad 等 regular 宽度下使用双栏：左栏附近看点，右栏收集与发现流。
  private var isWideLayout: Bool {
    horizontalSizeClass == .regular
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          EditorialHeader(
            eyebrow: nil,
            title: "探索",
            message: "看看附近的现场，翻翻你的收集，每天再认识一个新的文化细节。"
          )

          if isWideLayout {
            HStack(alignment: .top, spacing: 32) {
              VStack(alignment: .leading, spacing: 28) {
                nearbySection
              }
              .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

              VStack(alignment: .leading, spacing: 28) {
                collectionSection
                dailySection
                nextDiscoveriesSection
              }
              .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            }
          } else {
            nearbySection
            collectionSection
            dailySection
            nextDiscoveriesSection
          }
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("探索", showsBackButton: false)
    .task(id: reloadID) {
      await loadRecommendations()
    }
  }

  @ViewBuilder
  private var nearbySection: some View {
    sectionTitle("附近看点", subtitle: "离你最近的文化现场，点卡片看详情")
    recommendationContent
  }

  @ViewBuilder
  private var collectionSection: some View {
    if knowledgeStore != nil {
      sectionTitle("我的收集", subtitle: "已点亮的节点与进行中的主题")
      collectionCard
    }
  }

  @ViewBuilder
  private var dailySection: some View {
    if let daily = dailyElement {
      HStack(alignment: .firstTextBaseline) {
        sectionTitle("今日一物", subtitle: "每天轮换一个文化细节")
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

      DailyElementCard(
        element: daily,
        isCollected: contactedKeys.contains(daily.key)
      )
    }
  }

  @ViewBuilder
  private var nextDiscoveriesSection: some View {
    if !nextDiscoveries.isEmpty {
      sectionTitle("下一个看点", subtitle: "从你的图谱向外延伸")
      ForEach(nextDiscoveries, id: \.key) { element in
        NavigationLink(value: AppRoute.knowledgeElement(element.key)) {
          NextDiscoveryRow(element: element)
        }
        .buttonStyle(.plain)
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
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 8)

    case .loaded(let recommendations):
      ForEach(recommendations) { recommendation in
        NavigationLink(value: AppRoute.knowledgeElement(recommendation.culturalElement.key)) {
          NearbyIntroductionCard(
            recommendation: recommendation,
            isVisited: contactedKeys.contains(recommendation.culturalElement.key)
          )
        }
        .buttonStyle(.plain)
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
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
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

  // MARK: - 我的收集

  private var collectionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        Text("已收集 \(collectedCount) / \(sortedElements.count) 个节点")
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer(minLength: 12)
        NavigationLink(value: AppRoute.themes) {
          Text("全部主题")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.cinnabar)
        }
        .accessibilityIdentifier("explore.themesLink")
      }

      ProgressView(
        value: sortedElements.isEmpty
          ? 0
          : Double(collectedCount) / Double(sortedElements.count)
      )
      .tint(CultureTheme.cinnabar)

      if collectedCount == 0 {
        Text("还没有点亮任何节点。到扫描页拍下一个细节，或从下面的「今日一物」开始。")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      } else if activeThemes.isEmpty {
        Text("所有主题都已完成。")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      } else {
        ForEach(activeThemes, id: \.theme.key) { progress in
          NavigationLink(value: AppRoute.theme(progress.theme.key)) {
            HStack(alignment: .center, spacing: 12) {
              Text(progress.theme.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CultureTheme.inkPrimary)
                .lineLimit(1)
              Spacer(minLength: 8)
              ProgressView(value: progress.fractionComplete)
                .tint(CultureTheme.antiqueGold)
                .frame(width: 72)
              Text(progress.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(CultureTheme.inkSecondary)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .accessibilityIdentifier("explore.collectionCard")
  }

  private func sectionTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.cultureSerif(.title2))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
  }
}

private enum RecommendationState {
  case loading
  case loaded([AttractionIntroductionRecommendation])
  case empty
  case failed(String)
}

// MARK: - 附近看点卡片

private struct NearbyIntroductionCard: View {
  let recommendation: AttractionIntroductionRecommendation
  var isVisited: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(recommendation.name)
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer(minLength: 12)
        if isVisited {
          Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(CultureTheme.cinnabar)
            .accessibilityLabel("已到访")
        }
        Text(distanceText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(CultureTheme.cinnabar)
      }

      Label(
        "\(recommendation.attraction.name) · \(recommendation.culturalElement.name)",
        systemImage: "mappin.and.ellipse"
      )
      .font(.caption)
      .foregroundStyle(CultureTheme.inkSecondary)

      Text(recommendation.introduction.plainText)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(3)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
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

// MARK: - 今日一物卡片

private struct DailyElementCard: View {
  let element: KnowledgePack.Element
  let isCollected: Bool

  var body: some View {
    NavigationLink(value: AppRoute.knowledgeElement(element.key)) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          LocalizedPackText(
            source: element.name,
            cacheNamespace: "element",
            cacheKey: element.key
          )
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)

          Spacer(minLength: 12)

          Label(
            isCollected ? "已收集" : "未收集",
            systemImage: isCollected ? "checkmark.seal.fill" : "circle.dashed"
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(
            isCollected ? CultureTheme.cinnabar : CultureTheme.inkSecondary
          )
        }

        LocalizedPackText(
          source: element.introduction.plainText,
          cacheNamespace: "element",
          cacheKey: element.key,
          kind: .fragment
        )
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(3)
      }
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        CultureTheme.surface,
        in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
      )
      .overlay {
        RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
          .stroke(CultureTheme.hairline, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("explore.dailyCard")
  }
}

// MARK: - 下一个看点行

private struct NextDiscoveryRow: View {
  let element: KnowledgePack.Element

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        LocalizedPackText(
          source: element.name,
          cacheNamespace: "element",
          cacheKey: element.key
        )
        .font(.headline)
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

      Image(systemName: "chevron.right")
        .font(.body.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
        .accessibilityHidden(true)
    }
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 20, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
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
