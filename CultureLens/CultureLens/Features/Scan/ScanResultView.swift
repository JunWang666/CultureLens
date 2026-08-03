import SwiftData
import SwiftUI

struct ScanResultView: View {
  let session: ScanSession

  @Environment(\.modelContext) private var modelContext
  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @State private var isSaving = false
  @State private var saveError: String?
  @State private var explanationState: ExplanationLoadState = .idle
  @State private var explanationStreamSource: GrowingMarkdownSource?
  @State private var knowledgeContextSummary = "从你的文化图谱调整解释深度"
  private let explanationService = CultureExplanationService.live()

  private var object: CultureObject {
    session.result.object
  }

  private var isInCultureGraph: Bool {
    knowledgeProgressStore.isInGraph(
      object.id,
      elementKey: object.culturalElementKey
    )
  }

  private var rationale: String {
    session.result.rationale
  }

  private var primaryObject: CultureObject {
    session.result.object
  }

  private var attractionCandidates: [RecognitionCandidate] {
    session.result.displayAttractionCandidates
  }

  private var visualAlternatives: [RecognitionCandidate] {
    session.result.displayVisualAlternatives
  }

  private var currentResolutionStatus: String? {
    return session.result.resolutionStatus
  }

  private var introductionDocument: RichTextDocument? {
    if let key = object.culturalElementKey {
      return KnowledgeStore.shared?.introductionDocument(elementKey: key)
    }
    return KnowledgeStore.shared?.introductionDocument(nodeID: object.id)
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      SplitDetailLayout(topPadding: 16, bottomPadding: 40) { isWide in
        // 分栏布局下对象名提到左栏顶部（导航栏只显示“扫描结果”）
        if isWide {
          Text(object.canonicalName)
            .font(.cultureSerif(.largeTitle))
            .foregroundStyle(CultureTheme.inkPrimary)
        }

        imageHeader(height: isWide ? 340 : 280)
        identity(showTitle: !isWide)
        actionButtons
      } trailing: { _ in
        explanationSection
        CultureRelationGraphView(
          object: primaryObject,
          presentation: .expandablePreview
        )
        alternatives
        evidenceCard
      }
    }
    .cultureNavigationTitle(
      "扫描结果",
      prefersLeadingTitle: true,
      accessibilityIdentifier: "result.title"
    )
    .alert(
      "无法保存",
      isPresented: Binding(
        get: { saveError != nil },
        set: { if !$0 { saveError = nil } }
      )
    ) {
      Button("好", role: .cancel) {
        saveError = nil
      }
    } message: {
      Text(saveError ?? "")
    }
    .task(id: session.id) {
      await loadExplanation()
    }
  }

  private func imageHeader(height: CGFloat) -> some View {
    DataImageView(data: session.imageData)
      .frame(height: height)
      .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(alignment: .topLeading) {
        Label(
          session.isDemo ? "演示结果" : "视觉模型结果",
          systemImage: session.isDemo ? "theatermasks" : "sparkles"
        )
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(14)
      }
  }

  private func identity(showTitle: Bool) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(confidenceText, systemImage: confidenceSymbol)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.cinnabar)

      if currentResolutionStatus == "resolved" {
        Label("知识库已收录", systemImage: "checkmark.seal.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      // 单列布局下对象名显示在这里；分栏时已提到左栏顶部
      if showTitle {
        Text(object.canonicalName)
          .font(.cultureSerif(.largeTitle))
          .foregroundStyle(CultureTheme.inkPrimary)
      }

      Text(
        [object.category.rawValue, object.timePeriod, object.region]
          .compactMap { $0 }
          .joined(separator: " · ")
      )
      .font(.subheadline)
      .foregroundStyle(CultureTheme.inkSecondary)

      if let introductionDocument, !introductionDocument.blocks.isEmpty {
        RichTextBlocksView(
          document: introductionDocument,
          textFont: .title3,
          textColor: CultureTheme.inkPrimary
        )
      } else {
        Text(object.summary)
          .font(.title3)
          .foregroundStyle(CultureTheme.inkPrimary)
          .lineSpacing(6)
      }
    }
  }

  @ViewBuilder
  private var explanationSection: some View {
    switch explanationState {
    case .idle, .loading(_):
      HStack(spacing: 10) {
        ProgressView()
        VStack(alignment: .leading, spacing: 3) {
          Text("正在整理文化背景…")
            .font(.subheadline.weight(.semibold))
          Text(knowledgeContextSummary)
            .font(.caption)
        }
        .foregroundStyle(CultureTheme.inkSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
    case .streaming:
      if let explanationStreamSource {
        StreamingPersonalizedExplanationView(
          source: explanationStreamSource,
          knowledgeContextSummary: knowledgeContextSummary
        )
        .id(ObjectIdentifier(explanationStreamSource))
      }
    case .loaded(let explanation):
      PersonalizedExplanationView(
        explanation: explanation,
        knowledgeContextSummary: knowledgeContextSummary
      )
    case .partial(let explanation, let message):
      VStack(alignment: .leading, spacing: 12) {
        PersonalizedExplanationView(
          explanation: explanation,
          knowledgeContextSummary: knowledgeContextSummary
        )
        Label("连接中断，已保留收到的内容。\(message)", systemImage: "wifi.exclamationmark")
          .font(.footnote)
          .foregroundStyle(CultureTheme.cinnabar)
        Button("重新生成") {
          Task { await loadExplanation() }
        }
        .buttonStyle(.bordered)
      }
    case .failed(let message):
      VStack(alignment: .leading, spacing: 10) {
        Label("文化背景暂不可用", systemImage: "exclamationmark.bubble")
          .font(.headline)
          .foregroundStyle(CultureTheme.cinnabar)
        Text(message)
          .font(.footnote)
          .foregroundStyle(CultureTheme.inkSecondary)
        Button("重试") {
          Task { await loadExplanation() }
        }
        .buttonStyle(.bordered)
      }
      .padding(16)
      .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
    }
  }

  private var evidenceCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("判断依据", systemImage: "eye")
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(rationale)
        .font(.body)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineSpacing(5)

      if let uncertainty = session.result.uncertainty {
        Divider()
        Label("仍需确认", systemImage: "questionmark.circle")
          .font(.headline)
          .foregroundStyle(CultureTheme.cinnabar)
        Text(uncertainty)
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      Divider()

      HStack {
        Label(
          session.result.usedPlaceContext
            ? (session.place?.displayName ?? "使用位置")
            : "未使用位置",
          systemImage: session.result.usedPlaceContext ? "location.fill" : "location.slash"
        )
        Spacer()
        Text(session.result.modelIdentifier)
          .lineLimit(1)
      }
      .font(.caption)
      .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(20)
    .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var alternatives: some View {
    if !visualAlternatives.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(object.confidence < 0.8 ? "也可能是" : "其他视觉猜测")
          .font(.cultureSerif(.title2))
          .foregroundStyle(CultureTheme.inkPrimary)

        Text("来自识别模型的备选判断，与画面特征相关。")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)

        ForEach(visualAlternatives) { candidate in
          visualAlternativeRow(candidate)
        }
      }
    }

    if !attractionCandidates.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("附近景点候选")
          .font(.cultureSerif(.title2))
          .foregroundStyle(CultureTheme.inkPrimary)

        ForEach(attractionCandidates) { candidate in
          NavigationLink(
            value: AppRoute.scanCandidate(
              sessionID: session.id,
              candidateID: candidate.id
            )
          ) {
            candidateRow(
              name: candidate.canonicalName,
              summary: candidate.informativeSummary
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func visualAlternativeRow(_ candidate: RecognitionCandidate) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Text(candidate.canonicalName)
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Text(
          candidate.confidence,
          format: .percent.precision(.fractionLength(0))
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(CultureTheme.cinnabar)
      }
      Text(candidate.rationale)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
      if let summary = candidate.informativeSummary {
        Text(summary)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .lineLimit(2)
      }
      Label(candidate.category.rawValue, systemImage: "eye")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(16)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 18)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }

  private func candidateRow(
    name: String,
    summary: String?
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(name)
          .font(.headline)
          .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      if let summary {
        Text(summary)
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      Label("查看候选详情", systemImage: "location.fill")
        .font(.caption.weight(.semibold))
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(16)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 18)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  private var actionButtons: some View {
    VStack(spacing: 12) {
      if isInCultureGraph {
        Label("已加入文化图谱", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 12) {
        NavigationLink(value: AppRoute.ask(object.id)) {
          Label("继续追问这个对象", systemImage: "text.bubble")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CultureTheme.inkPrimary)
        .controlSize(.large)

        if isInCultureGraph {
          NavigationLink(value: AppRoute.object(object.id)) {
            Label("阅读完整解释", systemImage: "book.pages")
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.inkPrimary)
          .controlSize(.large)
        } else {
          Button {
            save()
          } label: {
            if isSaving {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Label("确认并保存到文化图谱", systemImage: "point.3.connected.trianglepath.dotted")
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.cinnabar)
          .controlSize(.large)
          .disabled(isSaving)
          .accessibilityIdentifier("result.save")
        }
      }

      if session.isDemo {
        Text("演示结果会保存到本机历史，但不代表真实视觉识别。")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var confidenceText: String {
    let prefix = object.confidence >= 0.8 ? "较高可信度" : "可能是"
    let percentage = object.confidence.formatted(
      .percent.precision(.fractionLength(0))
    )
    return "\(prefix) · \(percentage)"
  }

  private var confidenceSymbol: String {
    object.confidence >= 0.8 ? "checkmark.seal.fill" : "questionmark.diamond.fill"
  }

  private func save() {
    isSaving = true
    Task {
      do {
        let path = try await ScanMediaStore.shared.saveJPEG(
          session.imageData,
          id: session.id
        )
        let place = session.place
        let snapshotData = try JSONEncoder().encode(
          ScanHistorySnapshot(
            result: session.result,
            selectedObject: object,
            selectedCandidateID: nil
          )
        )
        let record = ScanHistoryRecord(
          recordID: session.id,
          createdAt: session.createdAt,
          cultureObjectID: object.id,
          canonicalName: object.canonicalName,
          categoryRawValue: object.category.rawValue,
          summary: object.summary,
          timePeriod: object.timePeriod,
          region: object.region,
          confidence: object.confidence,
          latitude: place?.latitude,
          longitude: place?.longitude,
          placeName: place?.displayName,
          imageRelativePath: path,
          modelIdentifier: session.result.modelIdentifier,
          resultSnapshotData: snapshotData
        )
        modelContext.insert(record)
        try modelContext.save()
        knowledgeProgressStore.setLevel(
          .contact,
          for: object.id,
          source: .manual,
          elementKey: object.culturalElementKey
        )
      } catch {
        saveError = error.localizedDescription
      }
      isSaving = false
    }
  }

  @MainActor
  private func loadExplanation() async {
    explanationStreamSource?.finish()

    let userKnowledgeStates = knowledgeProgressStore.userKnowledgeStates(
      knowledgeStore: KnowledgeStore.shared
    )
    knowledgeContextSummary = knowledgeContextSummary(for: userKnowledgeStates)

    guard let explanationService else {
      explanationState = .failed("讲解服务暂不可用。")
      return
    }
    // Demo / sample recognition should not call the live chat gateway.
    if session.isDemo {
      explanationState = .loaded(
        PersonalizedExplanation(
          markdown: demoExplanationMarkdown,
          citations: [
            KnowledgeCitation(
              key: object.culturalElementKey ?? object.id.uuidString,
              name: object.canonicalName,
              fragment: object.summary
            )
          ],
          modelIdentifier: "local-demo"
        )
      )
      return
    }

    let streamSource = GrowingMarkdownSource()
    explanationStreamSource = streamSource
    explanationState = .loading(isThinking: false)
    var latestBody = ""
    var modelIdentifier = LLMGatewayConfig.chat.model

    do {
      for try await event in explanationService.streamExplanation(
        result: session.result,
        userKnowledgeStates: userKnowledgeStates,
        siteContext: [
          session.place?.displayName,
          session.result.locationInfluence?.summary,
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "；")
      ) {
        try Task.checkCancellation()
        switch event {
        case .thinking:
          if latestBody.isEmpty {
            explanationState = .loading(isThinking: true)
          }
        case .delta(let snapshot):
          let body = CultureChatService.displayBody(from: snapshot)
          guard !body.isEmpty else { continue }
          latestBody = body
          explanationState = .streaming
          streamSource.yield(body)
        case .finished(let model, let content):
          modelIdentifier = model
          let parsed = CultureChatService.parseAnswer(content)
          latestBody = parsed.body
          streamSource.finish()
          explanationState = .loaded(
            PersonalizedExplanation(
              markdown: parsed.body,
              citations: parsed.citations,
              modelIdentifier: model
            )
          )
        }
      }

      if let key = object.culturalElementKey,
        knowledgeProgressStore.level(for: object.id, elementKey: key) == nil
      {
        knowledgeProgressStore.setLevel(
          .contact,
          for: object.id,
          source: .explanation,
          elementKey: key
        )
      }
    } catch {
      streamSource.finish()
      guard !Task.isCancelled else { return }
      if !latestBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        explanationState = .partial(
          PersonalizedExplanation(
            markdown: latestBody,
            citations: [],
            modelIdentifier: modelIdentifier
          ),
          message: error.localizedDescription
        )
      } else {
        explanationState = .failed(error.localizedDescription)
      }
    }
  }

  private func knowledgeContextSummary(
    for states: [UserKnowledgeStateContext]
  ) -> String {
    guard !states.isEmpty else {
      return "你的文化图谱暂无已有节点，将从必要背景讲起"
    }
    let deeperCount = states.filter { $0.level != KnowledgeLevel.contact.rawValue }.count
    if deeperCount > 0 {
      return "已结合文化图谱中 \(states.count) 个节点，其中 \(deeperCount) 个已理解或掌握"
    }
    return "已结合文化图谱中 \(states.count) 个接触过的节点补齐基础"
  }

  private var demoExplanationMarkdown: String {
    let relatedNames = object.concepts.prefix(2).map(\.name).joined(separator: "、")
    let nextStep =
      relatedNames.isEmpty
      ? "- 从关系图选择一个相邻概念继续探索。"
      : "- 继续观察或追问它与\(relatedNames)的关系。"
    return """
      ## 文化背景
      \(object.summary)

      ## 下一步建议
      \(nextStep)
      """
  }
}

#Preview {
  let result = RecognitionResult(
    id: UUID(),
    object: SampleCultureData.featured,
    alternatives: [],
    rationale: "根据木构件层叠与柱梁连接特征判断。",
    uncertainty: "仍需更清晰的屋檐整体照片确认时代。",
    modelIdentifier: "culturelens-sample-v1",
    usedPlaceContext: false,
    locationInfluence: nil
  )
  let session = ScanSession(
    id: result.id,
    imageData: Data(),
    result: result,
    place: nil,
    createdAt: Date(),
    isDemo: true
  )

  NavigationStack {
    ScanResultView(session: session)
  }
  .environment(KnowledgeProgressStore())
  .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
