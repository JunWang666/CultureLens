import SwiftUI
import UIKit

/// Prepares LLM copy (+ optional Seedream cover) then exposes a system ShareLink.
struct ShareVisitTripButton: View {
  let trip: VisitTrip
  var label: ShareLabel = .titled

  enum ShareLabel {
    case icon
    case titled
  }

  @Environment(AppLanguageStore.self) private var languageStore
  @Environment(ImageGenerationPreferenceStore.self) private var imageGenerationStore

  @State private var shareItem: VisitTripShareItem?
  @State private var isPreparing = false
  @State private var prepareFailed = false

  var body: some View {
    Group {
      if let shareItem {
        ShareLink(
          item: shareItem,
          preview: SharePreview(
            trip.title,
            image: Image(uiImage: shareItem.image ?? UIImage())
          )
        ) {
          labelView
        }
        .accessibilityLabel("分享文化回顾")
      } else if isPreparing {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: label == .titled ? .infinity : nil)
          .accessibilityLabel("正在准备分享")
      } else {
        Button {
          Task { await prepareShare(force: true) }
        } label: {
          labelView
        }
        .accessibilityLabel(prepareFailed ? "重试分享文化回顾" : "分享文化回顾")
      }
    }
    .task(id: trip.id) {
      await prepareShare(force: false)
    }
  }

  @ViewBuilder
  private var labelView: some View {
    switch label {
    case .icon:
      Image(systemName: "square.and.arrow.up")
    case .titled:
      Label("分享这次回顾", systemImage: "square.and.arrow.up")
        .frame(maxWidth: .infinity)
    }
  }

  @MainActor
  private func prepareShare(force: Bool) async {
    if shareItem != nil, !force { return }
    guard !isPreparing else { return }
    isPreparing = true
    defer { isPreparing = false }

    let language = languageStore.language
    let copy: VisitTripShareCopy
    do {
      copy = try await VisitTripShareCopyService.shared.copy(for: trip, language: language)
      prepareFailed = false
    } catch {
      copy = VisitTripShareCopyService.fallbackCopy(for: trip, language: language)
      prepareFailed = true
    }

    let hero = await loadHeroImage()
    let image = VisitTripShareRenderer.image(
      for: trip,
      blurb: copy.blurb,
      heroImage: hero
    )
    shareItem = VisitTripShareItem(trip: trip, blurb: copy.blurb, image: image)
  }

  /// Prefer the first introduction photo; optionally Seedream when enabled and missing.
  @MainActor
  private func loadHeroImage() async -> UIImage? {
    if let url = VisitTripHero.imageURL(for: trip) {
      if let data = try? await RemoteImageCache.shared.data(for: url),
        let image = UIImage(data: data)
      {
        return image
      }
    }

    guard imageGenerationStore.isEnabled else { return nil }

    let prompt = seedreamPrompt(language: languageStore.language)
    do {
      let data = try await VolcengineImageClient().generateImageData(prompt: prompt)
      return UIImage(data: data)
    } catch {
      #if DEBUG
        print("ShareVisitTripButton: Seedream failed \(error)")
      #endif
      return nil
    }
  }

  private func seedreamPrompt(language: AppLanguage) -> String {
    let objects = trip.objects.prefix(4).map(\.canonicalName).joined(separator: "、")
    let places = trip.attractionNames.prefix(3).joined(separator: "、")
    switch language {
    case .zhHans:
      return """
        文化旅行杂志封面，竖构图，克制留白，暖宣纸色调与朱砂点缀。\
        主题：\(trip.title)。地点：\(places.isEmpty ? trip.title : places)。\
        相关对象：\(objects.isEmpty ? "文化现场" : objects)。\
        无文字、无水印、无 logo，摄影感与平面海报之间，适合作为分享主图。
        """
    case .english:
      return """
        Editorial cultural-travel magazine cover, vertical composition, warm paper tones \
        with cinnabar accents, quiet negative space. Theme: \(trip.title). \
        Places: \(places.isEmpty ? trip.title : places). \
        Related subjects: \(objects.isEmpty ? "heritage site" : objects). \
        No text, no watermark, no logo.
        """
    }
  }
}
