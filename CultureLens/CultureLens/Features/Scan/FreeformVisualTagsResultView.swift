import SwiftUI

/// Dedicated fallback for photos that do not match an existing cultural point.
/// It deliberately avoids object-detail actions: freeform tags are observations
/// of this image, not a substitute for a pack-backed cultural identity.
struct FreeformVisualTagsResultView: View {
  let session: ScanSession

  private var result: RecognitionResult { session.result }

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        VStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
          MagazinePageHeader(
            eyebrow: "OPEN LOOK",
            title: "画面观察",
            message: "未匹配到已有兴趣点，以下是模型对当前画面的可见线索。"
          )

          if !session.imageData.isEmpty {
            imageHeader
          }

          observationIntro
          tagGrid
          evidenceSection

          if let uncertainty = result.uncertainty,
            !uncertainty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            uncertaintySection(uncertainty)
          }

          MagazineFooterOrnament()
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
    }
  }

  private var imageHeader: some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: 280)
      .overlay {
        DataImageView(data: session.imageData)
      }
      .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(alignment: .topLeading) {
        Label("自由视觉标签", systemImage: "eye")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(.ultraThinMaterial, in: Capsule())
          .padding(14)
      }
  }

  private var observationIntro: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("未匹配到已有兴趣点", systemImage: "questionmark.circle")
        .font(CultureTypography.body(.subheadline).weight(.semibold))
        .foregroundStyle(CultureTheme.cinnabar)

      Text(result.object.summary)
        .font(CultureTypography.body(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)
        .lineSpacing(4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.vertical, 4)
  }

  private var tagGrid: some View {
    VStack(alignment: .leading, spacing: 16) {
      MagazineSectionHeader(
        eyebrow: "VISUAL TAGS",
        "画面标签",
        subtitle: "模型从当前画面提取的可见线索。"
      )

      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
        alignment: .leading,
        spacing: 12
      ) {
        ForEach(result.visualTags) { tag in
          VisualTagLedgerEntry(tag: tag)
        }
      }
    }
  }

  private var evidenceSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("画面依据")
        .font(CultureTypography.title(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(result.rationale)
        .font(CultureTypography.body(.body))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(5)
    }
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { EditorialRule() }
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private func uncertaintySection(_ uncertainty: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("还需要确认")
        .font(CultureTypography.title(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(uncertainty)
        .font(CultureTypography.body(.body))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(5)
    }
    .padding(.vertical, 20)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(alignment: .top) { EditorialRule() }
    .overlay(alignment: .bottom) { EditorialRule() }
  }
}

private struct VisualTagLedgerEntry: View {
  let tag: VisualTag

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(tag.label, systemImage: "eye")
        .font(CultureTypography.body(.headline))
        .foregroundStyle(CultureTheme.inkPrimary)
        .fixedSize(horizontal: false, vertical: true)

      Text(tag.evidence)
        .font(CultureTypography.body(.caption))
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
    .padding(14)
    .overlay {
      Rectangle()
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  FreeformVisualTagsResultView(
    session: ScanSession(
      id: UUID(),
      imageData: Data(),
      result: RecognitionResult(
        id: UUID(),
        object: CultureObject(
          id: UUID(),
          canonicalName: "未收录画面",
          summary: "画面中的构件与色彩线索不足以可靠对应到现有兴趣点。",
          category: .other,
          confidence: 0.2,
          artworkSymbol: "eye",
          concepts: [],
          relations: [],
          sources: []
        ),
        alternatives: [],
        visualTags: [
          VisualTag(label: "层叠出跳", evidence: "水平构件向外逐层延伸，形成连续阴影。"),
          VisualTag(label: "风化石材", evidence: "表面有不规则浅色剥蚀与颗粒质感。"),
          VisualTag(label: "青绿设色", evidence: "局部保留青绿色彩，与深色底面形成对比。"),
        ],
        rationale: "只依据当前画面中可见的结构、材质与色彩关系生成标签。",
        uncertainty: "补拍完整轮廓和近距离纹样，可能有助于找到对应兴趣点。",
        modelIdentifier: "preview",
        usedPlaceContext: false,
        resolutionStatus: "unresolved"
      ),
      place: nil,
      createdAt: .now,
      isDemo: false
    )
  )
}
