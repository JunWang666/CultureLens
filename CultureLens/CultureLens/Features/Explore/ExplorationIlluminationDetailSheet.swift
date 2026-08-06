import SwiftUI

/// The one selected item in the illumination atlas. This stays local to the
/// Explore screen because it only controls its own presentation.
enum ExplorationIlluminationDetail: Identifiable {
  case city(IlluminatedCity)
  case badge(ExplorationBadge)

  var id: String {
    switch self {
    case .city(let city): "city-\(city.id)"
    case .badge(let badge): "badge-\(badge.id)"
    }
  }
}

struct ExplorationIlluminationDetailSheet: View {
  let detail: ExplorationIlluminationDetail
  let snapshot: ExplorationMilestoneSnapshot

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ZStack {
        CulturePageBackground()

        ScrollView {
          Group {
            switch detail {
            case .city(let city):
              IlluminatedCityDetail(city: city)
            case .badge(let badge):
              ExplorationBadgeDetail(badge: badge, snapshot: snapshot)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, CultureTheme.pagePadding)
          .padding(.top, 16)
          .padding(.bottom, 32)
        }
      }
      .navigationTitle(navigationTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("关闭") {
            dismiss()
          }
        }
      }
    }
  }

  private var navigationTitle: LocalizedStringKey {
    switch detail {
    case .city:
      "点亮城市"
    case .badge:
      "文化徽章"
    }
  }
}

struct IlluminatedCityPill: View {
  let city: IlluminatedCity

  var body: some View {
    HStack(spacing: 7) {
      Circle()
        .fill(CultureTheme.antiqueGold)
        .frame(width: 7, height: 7)
        .shadow(color: CultureTheme.antiqueGold.opacity(0.8), radius: 5)
      Text(city.name)
        .font(.subheadline.weight(.semibold))
      Text("\(city.scanCount)")
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.55))
    }
    .foregroundStyle(Color.white)
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(Color.white.opacity(0.09), in: Capsule())
    .contentShape(Capsule())
  }
}

private struct IlluminatedCityDetail: View {
  let city: IlluminatedCity

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 16) {
        CityFootprintArtwork(cityName: city.name)

        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: "ILLUMINATED CITY")
            .font(CultureTypography.eyebrow(.caption))
            .tracking(1.8)
            .foregroundStyle(CultureTheme.cinnabar)

          Text(city.name)
            .font(CultureTypography.title(.title))
            .foregroundStyle(CultureTheme.inkPrimary)

          Text("已点亮")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.cinnabar)
        }
      }

      MagazineDoubleRule()

      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(city.scanCount)")
          .font(CultureTypography.display(size: 52))
          .foregroundStyle(CultureTheme.inkPrimary)
        Text("次足迹")
          .font(CultureTypography.body(.title3))
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      Text(String(localized: "已点亮城市 \(city.name)，\(city.scanCount) 次足迹"))
        .font(CultureTypography.body(.body))
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ExplorationBadgeDetail: View {
  let badge: ExplorationBadge
  let snapshot: ExplorationMilestoneSnapshot

  private var progressMetrics: [ExplorationBadgeProgressMetric] {
    switch badge.kind {
    case .firstLight:
      [
        .init(id: "nodes", value: snapshot.litNodeCount, target: 1, title: "点亮节点")
      ]
    case .seriesBearer:
      [
        .init(id: "series", value: snapshot.completedSeriesCount, target: 1, title: "文化系")
      ]
    case .cityLantern:
      [
        .init(id: "cities", value: snapshot.cities.count, target: 1, title: "城市")
      ]
    case .fieldNotes:
      [
        .init(id: "visits", value: snapshot.scanCount, target: 5, title: "足迹")
      ]
    case .constellation:
      [
        .init(id: "nodes", value: snapshot.litNodeCount, target: 10, title: "点亮节点")
      ]
    case .cultureKeeper:
      [
        .init(id: "series", value: snapshot.completedSeriesCount, target: 3, title: "文化系"),
        .init(id: "cities", value: snapshot.cities.count, target: 2, title: "城市"),
      ]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 16) {
        ZStack {
          Circle()
            .fill(CultureTheme.antiqueGold.opacity(badge.isUnlocked ? 0.16 : 0.07))
          Circle()
            .stroke(
              badge.isUnlocked ? CultureTheme.antiqueGold : CultureTheme.inkSecondary.opacity(0.24),
              lineWidth: 1
            )
          Image(ExplorationArtwork.badgeImageName(for: badge.kind))
            .resizable()
            .scaledToFill()
            .frame(width: 82, height: 82)
            .clipShape(Circle())
            .saturation(badge.isUnlocked ? 1 : 0)
            .opacity(badge.isUnlocked ? 1 : 0.32)
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 6) {
          Text(verbatim: "CULTURE BADGE")
            .font(CultureTypography.eyebrow(.caption))
            .tracking(1.8)
            .foregroundStyle(CultureTheme.cinnabar)

          Text(badge.kind.title)
            .font(CultureTypography.title(.title2))
            .foregroundStyle(CultureTheme.inkPrimary)

          Text(badge.isUnlocked ? "已点亮" : "继续探索")
            .font(.caption.weight(.semibold))
            .foregroundStyle(badge.isUnlocked ? CultureTheme.cinnabar : CultureTheme.inkSecondary)
        }
      }

      MagazineDoubleRule()

      Text(badge.kind.detail)
        .font(CultureTypography.body(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(alignment: .top, spacing: 16) {
        ForEach(progressMetrics) { metric in
          ExplorationBadgeProgressView(metric: metric)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private struct ExplorationBadgeProgressMetric: Identifiable {
  let id: String
  let value: Int
  let target: Int
  let title: LocalizedStringKey
}

private struct ExplorationBadgeProgressView: View {
  let metric: ExplorationBadgeProgressMetric

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("\(min(metric.value, metric.target))/\(metric.target)")
        .font(CultureTypography.display(size: 30))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(metric.title)
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
      ThinProgressRule(
        fraction: Double(metric.value) / Double(metric.target),
        tint: CultureTheme.cinnabar
      )
      .frame(maxWidth: 150)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A textual city marker rather than another system pictogram. It makes the
/// per-city sheet feel personal without claiming a geographic illustration.
private struct CityFootprintArtwork: View {
  let cityName: String

  private var monogram: String {
    String(cityName.prefix(1))
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(CultureTheme.cinnabar)

      Path { path in
        path.move(to: CGPoint(x: 10, y: 66))
        path.addLine(to: CGPoint(x: 34, y: 38))
        path.addLine(to: CGPoint(x: 58, y: 66))
      }
      .stroke(CultureTheme.antiqueGold.opacity(0.9), lineWidth: 1)

      Circle()
        .fill(CultureTheme.antiqueGold.opacity(0.9))
        .frame(width: 8, height: 8)
        .offset(x: 26, y: -28)

      Text(verbatim: monogram)
        .font(CultureTypography.display(size: 38))
        .foregroundStyle(CultureTheme.canvas)
        .offset(y: 5)
    }
    .frame(width: 82, height: 82)
    .accessibilityHidden(true)
  }
}
