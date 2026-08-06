import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Prefers a rendered journal PNG; always offers readable text.
struct VisitTripShareItem: Transferable {
  let trip: VisitTrip
  let blurb: String
  let image: UIImage?

  nonisolated var text: String {
    VisitTripShareRenderer.shareText(for: trip, blurb: blurb)
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .png) { item in
      guard let data = item.image?.pngData() else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return data
    }
    ProxyRepresentation(exporting: { item in
      VisitTripShareRenderer.shareText(for: item.trip, blurb: item.blurb)
    })
  }
}

/// Magazine-style share surface for an entire cultural review.
struct VisitTripShareCard: View {
  let trip: VisitTrip
  let blurb: String
  var heroImage: UIImage? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topTrailing) {
        hero
        Text("CultureLens")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.92))
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(12)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text(verbatim: "JOURNAL")
          .font(CultureTypography.eyebrow(.caption))
          .tracking(2)
          .foregroundStyle(CultureTheme.cinnabar)

        Text(trip.title)
          .font(CultureTypography.title(.title2))
          .foregroundStyle(CultureTheme.inkPrimary)

        Text(trip.durationText)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)

        Text(blurb)
          .font(CultureTypography.body(.subheadline))
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineSpacing(3)
          .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 16) {
          shareStat("\(trip.litNodeCount)", "节点")
          shareStat("\(trip.attractionNames.count)", "景点")
          shareStat("\(trip.scanCount)", "识别")
        }
        .padding(.top, 4)

        if !trip.objects.isEmpty {
          Text(
            trip.objects.prefix(5).map(\.canonicalName).joined(separator: " · ")
          )
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineLimit(2)
        }
      }
      .padding(18)
    }
    .background(CultureTheme.surface)
    .clipShape(RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var hero: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: 200)
      .overlay {
        if let heroImage {
          Image(uiImage: heroImage)
            .resizable()
            .scaledToFill()
            .magazinePhoto()
        } else {
          ObjectArtwork(
            object: VisitTripHero.artworkObject(for: trip),
            height: 200
          )
        }
      }
      .clipped()
  }

  private func shareStat(_ value: String, _ label: LocalizedStringKey) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(CultureTypography.display(size: 22))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(label)
        .font(.caption2)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
  }
}

enum VisitTripShareRenderer {
  @MainActor
  static func image(
    for trip: VisitTrip,
    blurb: String,
    heroImage: UIImage?,
    width: CGFloat = 390
  ) -> UIImage? {
    let card = VisitTripShareCard(trip: trip, blurb: blurb, heroImage: heroImage)
      .frame(width: width)
      .environment(\.colorScheme, .light)
      .environment(AppLanguageStore())

    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    return renderer.uiImage
  }

  nonisolated static func shareText(for trip: VisitTrip, blurb: String) -> String {
    let objects = trip.objects.prefix(6).map(\.canonicalName).joined(separator: " · ")
    var lines = [
      trip.title,
      trip.durationText,
      blurb,
      "\(trip.litNodeCount) 节点 · \(trip.attractionNames.count) 景点 · \(trip.scanCount) 识别",
    ]
    if !objects.isEmpty {
      lines.append(objects)
    }
    lines.append("— CultureLens")
    return lines.joined(separator: "\n")
  }
}
