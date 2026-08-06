import SwiftData
import SwiftUI

struct ScanResultView: View {
  /// 页面展示模式：实时扫描（含候选）、足迹历史、知识节点（图谱/概念）。
  enum Presentation {
    case scan
    case history
    case knowledge
  }

  let session: ScanSession
  /// 非 nil 时页面展示某个候选（从景点推荐进入），复用扫描结果布局，
  /// 但不显示拍摄的照片（后续换成数据库图片）。
  var candidate: RecognitionCandidate? = nil
  var presentation: Presentation = .scan

  @Environment(\.modelContext) private var modelContext
  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore

  private var isAttractionCandidate: Bool {
    candidate?.resolutionStatus == "attraction"
  }

  private var object: CultureObject {
    guard let candidate else { return session.result.object }
    var result = candidate.cultureObject
    if let summary = candidate.informativeSummary {
      result.summary = summary
    }
    return result
  }

  /// 图谱成员判定用的元素 ID：候选页一律用其绑定的文化元素（景点候选的
  /// `culturalElementID` 就是绑定元素），不再把 attractionID 当元素存。
  private var graphElementID: UUID? {
    candidate?.culturalElementID ?? object.culturalElementID
  }

  /// 图谱成员身份统一为元素节点 UUID：景点页、候选页与节点页落在同一节点上，
  /// 跨扫描去重，且在用户图谱中始终是 pack-backed 节点而非游离节点。
  private var graphNodeID: UUID {
    if let id = graphElementID, KnowledgeStore.shared?.element(id: id) != nil {
      return id
    }
    return object.id
  }

  private var isInCultureGraph: Bool {
    knowledgeProgressStore.isInGraph(
      graphNodeID,
      elementID: graphElementID
    )
  }

  private var rationale: String {
    candidate?.rationale ?? session.result.rationale
  }

  /// 讲解服务的输入：候选没有独立识别结果，用主会话上下文包一层。
  private var explanationInput: RecognitionResult {
    guard let candidate else { return session.result }
    return RecognitionResult(
      id: candidate.id,
      object: object,
      alternatives: [],
      rationale: candidate.rationale,
      modelIdentifier: session.result.modelIdentifier,
      usedPlaceContext: session.result.usedPlaceContext,
      resolutionStatus: candidate.resolutionStatus
    )
  }

  /// 识别结果若已绑定知识库元素但 relations 为空（或候选页本身不带图谱），
  /// 用知识库相邻关系补齐，与识别映射的 fallback 关系构建保持一致。
  private var graphObject: CultureObject {
    guard object.relations.isEmpty else { return object }
    let store = KnowledgeStore.shared
    let elementID =
      object.culturalElementID
      ?? store?.elementID(matchingName: object.canonicalName)
      ?? (store?.element(id: object.id) != nil ? object.id : nil)
    guard let elementID, let store else { return object }
    let related = store.relatedElements(forID: elementID)
    guard !related.isEmpty else {
      // Even without edges, attach the ID so the empty-state can say「暂无关系边」
      // instead of「未匹配到知识库对象」.
      if object.culturalElementID == nil {
        var keyed = object
        keyed.culturalElementID = elementID
        keyed.id = elementID
        return keyed
      }
      return object
    }

    let explanation: String
    switch AppLanguageStore.currentLanguage() {
    case .english:
      explanation =
        "The culture content library records an explicit link between this object and the concept; the relation type is not yet refined."
    case .zhHans:
      explanation = "文化内容库记录了当前对象与该概念的显式关联；关系类型尚未细分。"
    }

    var enriched = object
    enriched.culturalElementID = elementID
    enriched.id = elementID
    enriched.concepts = related.map { element in
      CultureConcept(
        id: element.id,
        name: element.name,
        kind: CulturalElementPresentation.conceptKind(element.conceptKind),
        summary: KnowledgeStore.richTextPlainText(element.introduction),
        detail: ""
      )
    }
    enriched.relations = related.map { element in
      CultureRelation(
        id: DeterministicID.v5(
          name: elementID.uuidString + ":" + element.id.uuidString + ":" + "解释"
        ),
        sourceID: elementID,
        targetID: element.id,
        kind: .explains,
        explanation: explanation
      )
    }
    return enriched
  }

  private var attractionCandidates: [RecognitionCandidate] {
    session.result.displayAttractionCandidates
  }

  /// 景点推荐中的模型备选只保留命中景点 ID 的条目。
  private var visualAlternatives: [RecognitionCandidate] {
    session.result.displayVisualAlternatives.filter { $0.attractionID != nil }
  }

  private var currentResolutionStatus: String? {
    return session.result.resolutionStatus
  }

  /// Cache / localization key: prefer pack slug, fall back to UUID string.
  private var objectElementKey: String? {
    if let id = object.culturalElementID ?? (KnowledgeStore.shared?.element(id: object.id) != nil ? object.id : nil),
      KnowledgeStore.shared?.element(id: id) != nil
    {
      return KnowledgeStore.shared?.elementKey(for: id) ?? id.uuidString.lowercased()
    }
    return nil
  }

  private var objectElementID: UUID? {
    if let id = object.culturalElementID, KnowledgeStore.shared?.element(id: id) != nil {
      return id
    }
    if KnowledgeStore.shared?.element(id: object.id) != nil {
      return object.id
    }
    return nil
  }

  var body: some View {
    ZStack {
      CulturePageBackground()

      SplitDetailLayout(topPadding: 16, bottomPadding: 40) { isWide in
        // 分栏布局下对象名提到左栏顶部（导航栏只显示页面标题）
        if isWide {
          LocalizedPackText(
            source: object.canonicalName,
            cacheNamespace: "element",
            cacheKey: objectElementKey
          )
          .font(.cultureSerif(.largeTitle))
          .foregroundStyle(CultureTheme.inkPrimary)
        }

        // 候选页与知识节点页不显示拍摄的照片（候选后续换成数据库图片）；
        // 历史记录的图片可能已被清理，为空时同样不显示
        if candidate == nil && presentation != .knowledge && !session.imageData.isEmpty {
          imageHeader(height: isWide ? 340 : 280)
        }
        identity(showTitle: !isWide)
        actionButtons
        // 景点推荐：分栏（iPad）时放左栏，单列（iPhone）时放页面底部（见 trailing）；
        // 足迹历史不展示候选
        if isWide, presentation != .history {
          recommendations
        }
      } trailing: { isWide in
        ScanExplanationSectionView(
          result: explanationInput,
          isDemo: session.isDemo,
          siteContext: siteContext,
          onExplained: markExplained
        )
        if let candidate {
          if isAttractionCandidate, let attractionID = candidate.attractionID {
            AttractionIntroductionsView(
              place: session.place,
              attractionID: attractionID,
              existingSummary: candidate.informativeSummary
            )
            candidateContext
          } else {
            visualContext(candidate)
          }
        }
        // 文化脉络阶梯（AbstractionLadderView）现阶段对用户价值不大，先隐藏；
        // 组件保留在 DesignSystem 中，需要时恢复此调用即可。
        // 候选与知识节点的图谱数据由知识库补齐（见 graphObject），补不到关系时不展示
        if candidate == nil || !graphObject.relations.isEmpty {
          CultureRelationGraphView(
            object: graphObject,
            presentation: .expandablePreview
          )
        }
        if presentation != .knowledge {
          evidenceCard
        }
        // 足迹历史不展示候选
        if !isWide, presentation != .history {
          recommendations
        }
      }
    }
    .cultureNavigationTitle(
      navigationTitle,
      prefersLeadingTitle: true,
      accessibilityIdentifier: "result.title"
    )
    .task(id: session.id) {
      autoSaveIfNeeded()
    }
  }

  private var navigationTitle: LocalizedStringKey {
    if candidate != nil { return "候选详情" }
    switch presentation {
    case .knowledge:
      return LocalizedStringKey(object.canonicalName)
    case .scan, .history:
      return "扫描结果"
    }
  }

  /// 只固定高度时 scaledToFill 会把图片撑得比栏宽更宽（frame 跟随图片实际
  /// 渲染宽度），照片会溢出到右栏下方。先用透明占位把区域定死，再叠加图片
  /// 并裁剪，保证填满且不外溢。
  private func imageHeader(height: CGFloat) -> some View {
    Color.clear
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .overlay {
        DataImageView(data: session.imageData)
      }
      .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
      .overlay(alignment: .topLeading) {
        Label(
          session.isDemo ? LocalizedStringKey("演示结果") : "视觉模型结果",
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
      if let candidate {
        candidateKindLabel(candidate)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.cinnabar)
      } else if presentation == .knowledge {
        Label("知识库节点", systemImage: "sparkles")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.cinnabar)
      } else {
        Label(confidenceText, systemImage: confidenceSymbol)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.cinnabar)

        if currentResolutionStatus == "resolved", objectElementKey != nil {
          Label("知识库已收录", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(CultureTheme.inkSecondary)
        }
      }

      // 单列布局下对象名显示在这里；分栏时已提到左栏顶部
      if showTitle {
        LocalizedPackText(
          source: object.canonicalName,
          cacheNamespace: "element",
          cacheKey: objectElementKey
        )
        .font(.cultureSerif(.largeTitle))
        .foregroundStyle(CultureTheme.inkPrimary)
      }

      // 知识节点没有类别/年代/地区等识别元信息
      if presentation != .knowledge {
        Text(
          [object.category.localizedTitle, object.timePeriod, object.region]
            .compactMap { $0 }
            .joined(separator: " · ")
        )
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
      }

      LocalizedKnowledgeBlocksView(
        elementID: objectElementID,
        elementKey: objectElementKey,
        fallbackName: object.canonicalName,
        fallbackSummary: object.summary,
        textFont: .title3,
        textColor: CultureTheme.inkPrimary
      )
    }
  }

  /// 候选类型标签：与主结果页的可信度标签同一位置。景点候选显示来源，
  /// 视觉备选附带模型置信度。
  private func candidateKindLabel(_ candidate: RecognitionCandidate) -> some View {
    if candidate.resolutionStatus == "attraction" {
      return Label("附近景点候选", systemImage: "location.fill")
    }
    if candidate.confidence > 0 {
      let percent = candidate.confidence.formatted(
        .percent.precision(.fractionLength(0))
      )
      return Label("视觉备选 · \(percent)", systemImage: "eye")
    }
    return Label("视觉备选", systemImage: "eye")
  }

  /// 景点候选的说明卡。
  private var candidateContext: some View {
    Label(
      "根据本次扫描位置列为候选，尚未由画面确认。",
      systemImage: "location.fill"
    )
    .font(.subheadline)
    .foregroundStyle(CultureTheme.inkSecondary)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
  }

  /// 视觉备选的说明卡：模型的判断依据。
  private func visualContext(_ candidate: RecognitionCandidate) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("识别模型的备选判断，与画面特征相关。", systemImage: "eye")
      Text(candidate.rationale)
    }
    .font(.subheadline)
    .foregroundStyle(CultureTheme.inkSecondary)
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
    )
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

      if candidate == nil, let uncertainty = session.result.uncertainty {
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
            ? (session.place?.displayName ?? String(localized: "使用位置"))
            : String(localized: "未使用位置"),
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

  /// 景点推荐：视觉模型的备选猜测（在前，只保留命中景点 key 的）与附近景点候选。
  @ViewBuilder
  private var recommendations: some View {
    if !attractionCandidates.isEmpty || !visualAlternatives.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("景点推荐")
          .font(.cultureSerif(.title2))
          .foregroundStyle(CultureTheme.inkPrimary)

        Text("识别模型的备选判断与附近可确认的景点。")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)

        ForEach(visualAlternatives) { candidate in
          NavigationLink(
            value: AppRoute.scanCandidate(
              sessionID: session.id,
              candidateID: candidate.id
            )
          ) {
            visualAlternativeRow(candidate)
          }
          .buttonStyle(.plain)
        }

        ForEach(attractionCandidates) { candidate in
          NavigationLink(
            value: AppRoute.scanCandidate(
              sessionID: session.id,
              candidateID: candidate.id
            )
          ) {
            candidateRow(candidate)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func visualAlternativeRow(_ candidate: RecognitionCandidate) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        LocalizedPackText(
          source: candidate.canonicalName,
          cacheNamespace: "element",
          cacheKey: candidate.culturalElementID.map { $0.uuidString.lowercased() }
            ?? KnowledgeStore.shared?.elementKey(for: candidate.id)
        )
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Text(
          candidate.confidence,
          format: .percent.precision(.fractionLength(0))
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(CultureTheme.cinnabar)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      Text(candidate.rationale)
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
      if let summary = candidate.informativeSummary {
        LocalizedPackText(
          source: summary,
          cacheNamespace: "element",
          cacheKey: candidate.culturalElementID.map { $0.uuidString.lowercased() }
            ?? KnowledgeStore.shared?.elementKey(for: candidate.id),
          kind: .fragment
        )
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(2)
      }
      Label(candidate.category.localizedTitle, systemImage: "eye")
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

  private func candidateRow(_ candidate: RecognitionCandidate) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        LocalizedPackText(
          source: candidate.canonicalName,
          cacheNamespace: "attraction",
          cacheKey: candidate.attractionID.map { $0.uuidString.lowercased() }
          ?? KnowledgeStore.shared?.attraction(id: candidate.id).flatMap(\.key)
        )
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(CultureTheme.inkSecondary)
      }
      if let summary = candidate.informativeSummary {
        LocalizedPackText(
          source: summary,
          cacheNamespace: "attraction",
          cacheKey: candidate.attractionID.map { $0.uuidString.lowercased() }
          ?? KnowledgeStore.shared?.attraction(id: candidate.id).flatMap(\.key),
          kind: .fragment
        )
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .lineLimit(3)
      }
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

        if presentation == .knowledge {
          KnowledgeGraphMembershipButton(
            nodeID: object.id,
            elementID: objectElementID,
            presentation: .fullWidth
          )
        } else if isInCultureGraph {
          NavigationLink(value: AppRoute.object(object.id)) {
            Label("阅读完整解释", systemImage: "book.pages")
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.inkPrimary)
          .controlSize(.large)
        }
      }

      if session.isDemo, presentation == .scan {
        Text("演示结果会保存到本机历史，但不代表真实视觉识别。")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var confidenceText: LocalizedStringKey {
    let percentage = object.confidence.formatted(
      .percent.precision(.fractionLength(0))
    )
    if object.confidence >= 0.8 {
      return "较高可信度 · \(percentage)"
    }
    return "可能是 · \(percentage)"
  }

  private var confidenceSymbol: String {
    object.confidence >= 0.8 ? "checkmark.seal.fill" : "questionmark.diamond.fill"
  }

  /// 访问即存：扫描结果页/候选页出现时自动写入扫描历史，无需手动确认。
  /// 主结果仅在本次会话还没有历史记录时插入，避免覆盖候选页更新的选择；
  /// 候选页每次访问都把该候选写入/更新历史（没有可展示介绍时不生成记录）。
  /// 历史与知识节点模式不写入。
  private func autoSaveIfNeeded() {
    guard presentation == .scan else { return }
    if let candidate {
      guard candidate.informativeSummary != nil else { return }
      Task {
        try? await persist(selectedCandidateID: candidate.id)
      }
      return
    }

    let id = session.id
    let descriptor = FetchDescriptor<ScanHistoryRecord>(
      predicate: #Predicate { $0.recordID == id }
    )
    guard ((try? modelContext.fetchCount(descriptor)) ?? 0) == 0 else { return }
    Task {
      try? await persist(selectedCandidateID: nil)
    }
  }

  private func persist(selectedCandidateID: UUID?) async throws {
    let path = try await ScanMediaStore.shared.saveJPEG(
      session.imageData,
      id: session.id
    )
    let place = session.place
    // 坐标已有但缺少地名时（如照片 EXIF 定位）补一次逆地理编码，避免历史里显示“未记录位置”。
    var placeName = place?.displayName
    if (placeName?.isEmpty ?? true), let place {
      placeName = await LocationContextProvider.reverseDisplayName(
        latitude: place.latitude,
        longitude: place.longitude
      )
    }
    let snapshotData = try JSONEncoder().encode(
      ScanHistorySnapshot(
        result: session.result,
        selectedObject: object,
        selectedCandidateID: selectedCandidateID
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
      placeName: placeName,
      imageRelativePath: path,
      modelIdentifier: session.result.modelIdentifier,
      resultSnapshotData: snapshotData
    )
    modelContext.insert(record)
    try modelContext.save()
    knowledgeProgressStore.setLevel(
      .contact,
      for: graphNodeID,
      source: .manual,
      elementID: graphElementID
    )
  }

  private var siteContext: String? {
    let context = [
      session.place?.displayName,
      session.result.locationInfluence?.summary,
    ]
    .compactMap { $0 }
    .filter { !$0.isEmpty }
    .joined(separator: "；")
    return context.isEmpty ? nil : context
  }

  private func markExplained() {
    if let elementID = objectElementID,
      knowledgeProgressStore.level(for: object.id, elementID: elementID) == nil
    {
      knowledgeProgressStore.setLevel(
        .contact,
        for: object.id,
        source: .explanation,
        elementID: elementID
      )
    }
  }
}

extension ScanResultView {
  /// 知识节点展示入口：由知识库对象合成会话，复用扫描结果页布局。
  /// 与真实扫描一样走 AI 讲解（`streamExplanation`）；知识模式不写扫描历史。
  init(knowledgeObject object: CultureObject) {
    let result = RecognitionResult(
      id: object.id,
      object: object,
      alternatives: [],
      rationale: object.summary,
      modelIdentifier: "knowledge-pack",
      usedPlaceContext: false
    )
    self.init(
      session: ScanSession(
        id: object.id,
        imageData: Data(),
        result: result,
        place: nil,
        createdAt: Date(),
        isDemo: false
      ),
      presentation: .knowledge
    )
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
