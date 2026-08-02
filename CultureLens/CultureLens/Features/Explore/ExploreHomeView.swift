import Foundation
import SwiftUI

struct ExploreHomeView: View {
  let startScan: () -> Void
  private let contentService: CultureContentService

  @State private var locationProvider = LocationContextProvider()
  @State private var recommendationState: RecommendationState = .loading
  @State private var reloadID = UUID()

  init(
    contentService: CultureContentService = .live(),
    startScan: @escaping () -> Void
  ) {
    self.contentService = contentService
    self.startScan = startScan
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 28) {
          EditorialHeader(
            eyebrow: nil,
            title: "探索",
            message: "留意一处屋檐、一件器物或一段纹样。文化的线索，常从细节开始。"
          )

          sectionTitle("基于位置推荐", subtitle: "发现附近值得理解的文化线索")

          recommendationContent

          scanInvitation
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 40)
      }
    }
    .navigationTitle("探索")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: reloadID) {
      await loadRecommendations()
    }
  }

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
        NearbyIntroductionCard(recommendation: recommendation)
      }

    case .empty:
      recommendationNotice(
        title: "附近暂无已收录内容",
        message: "这里只显示数据库返回的内容，不再使用本地样例补位。",
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
    title: String,
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
        2
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

  private var scanInvitation: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Text("把镜头对准一个细节")
            .font(.cultureSerif(.title2))
          Text("拍摄后框选想理解的部分，让文化线索从眼前的细节展开。")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.76))
        }

        Spacer()

        Image(systemName: "viewfinder")
          .font(.largeTitle.weight(.light))
          .foregroundStyle(CultureTheme.antiqueGold)
      }

      Button(action: startScan) {
        Label("开始扫描", systemImage: "camera.viewfinder")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .tint(CultureTheme.cinnabar)
      .controlSize(.large)
      .accessibilityIdentifier("explore.startScan")
    }
    .foregroundStyle(.white)
    .padding(22)
    .background(
      LinearGradient(
        colors: [CultureTheme.inkPrimary, CultureTheme.inkPrimary.opacity(0.86)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: 26, style: .continuous)
    )
    .overlay(alignment: .bottomTrailing) {
      Circle()
        .stroke(CultureTheme.antiqueGold.opacity(0.32), lineWidth: 1)
        .frame(width: 140, height: 140)
        .offset(x: 44, y: 54)
        .allowsHitTesting(false)
    }
    .clipped()
  }

  private func sectionTitle(_ title: String, subtitle: String) -> some View {
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

private struct NearbyIntroductionCard: View {
  let recommendation: AttractionIntroductionRecommendation

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(recommendation.name)
          .font(.cultureSerif(.title3))
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer(minLength: 12)
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

  private var distanceText: String {
    if recommendation.distanceMeters < 1_000 {
      return "\(Int(recommendation.distanceMeters.rounded())) 米"
    }
    return String(format: "%.1f 公里", recommendation.distanceMeters / 1_000)
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
    ) {}
  }
}
