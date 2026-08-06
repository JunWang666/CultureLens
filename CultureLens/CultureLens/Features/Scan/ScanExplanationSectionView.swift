import SwiftUI

/// 扫描结果与候选详情共用的 AI 文化背景讲解区块：
/// 负责流式加载、骨架屏、断流保留与失败重试。演示模式不请求网关，
/// 也不显示任何本地拼凑的讲解——没有 LLM 请求就没有这个区块。
struct ScanExplanationSectionView: View {
  let result: RecognitionResult
  let isDemo: Bool
  let siteContext: String?
  /// 讲解加载成功后的回调（例如记录「接触」等级）。
  var onExplained: (() -> Void)? = nil

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @State private var explanationState: ExplanationLoadState = .idle
  @State private var explanationStreamSource: GrowingMarkdownSource?
  @State private var knowledgeContextSummary: LocalizedStringKey = "从你的文化图谱调整解释深度"
  @State private var operationNotice: String?
  private let explanationService = CultureExplanationService.live()

  var body: some View {
    if !isDemo {
      content
        .task(id: result.id) {
          await loadExplanation(forceRefresh: false)
        }
        .alert(
          "讲解操作未完成",
          isPresented: Binding(
            get: { operationNotice != nil },
            set: { if !$0 { operationNotice = nil } }
          )
        ) {
          Button("好", role: .cancel) {
            operationNotice = nil
          }
        } message: {
          Text(operationNotice ?? "")
        }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch explanationState {
    case .idle, .loading(_):
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          Text("正在整理文化背景…")
            .font(.subheadline.weight(.semibold))
          Text(knowledgeContextSummary)
            .font(.caption)
        }
        .foregroundStyle(CultureTheme.inkSecondary)
        SkeletonTextBlock()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 16)
      .overlay(alignment: .top) { EditorialRule() }
      .overlay(alignment: .bottom) { EditorialRule() }
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
        knowledgeContextSummary: knowledgeContextSummary,
        onRegenerate: {
          Task { await loadExplanation(forceRefresh: true) }
        }
      )
    case .regenerating(let explanation):
      PersonalizedExplanationView(
        explanation: explanation,
        knowledgeContextSummary: knowledgeContextSummary,
        isRegenerating: true
      )
    case .partial(let explanation, let message):
      VStack(alignment: .leading, spacing: 12) {
        PersonalizedExplanationView(
          explanation: explanation,
          knowledgeContextSummary: knowledgeContextSummary,
          onRegenerate: {
            Task { await loadExplanation(forceRefresh: true) }
          }
        )
        Label("连接中断，已保留收到的内容。\(message)", systemImage: "wifi.exclamationmark")
          .font(CultureTypography.body(.footnote))
          .foregroundStyle(CultureTheme.cinnabar)
      }
    case .failed(let message):
      VStack(alignment: .leading, spacing: 10) {
        Label("文化背景暂不可用", systemImage: "exclamationmark.bubble")
          .font(.headline)
          .foregroundStyle(CultureTheme.cinnabar)
        Text(message)
          .font(CultureTypography.body(.footnote))
          .foregroundStyle(CultureTheme.inkSecondary)
        Button("重试") {
          Task { await loadExplanation(forceRefresh: false) }
        }
        .buttonStyle(.bordered)
      }
      .padding(.vertical, 16)
      .overlay(alignment: .top) { EditorialRule() }
      .overlay(alignment: .bottom) { EditorialRule() }
    }
  }

  @MainActor
  private func loadExplanation(forceRefresh: Bool) async {
    let previousExplanation = forceRefresh ? currentExplanation : nil
    explanationStreamSource?.finish()
    operationNotice = nil

    let userKnowledgeStates = knowledgeProgressStore.userKnowledgeStates(
      knowledgeStore: KnowledgeStore.shared
    )
    knowledgeContextSummary = knowledgeContextSummary(for: userKnowledgeStates)

    let storageKey = CultureExplanationStore.key(
      result: result,
      siteContext: siteContext,
      language: AppLanguageStore.currentLanguage()
    )
    if !forceRefresh,
      let stored = await CultureExplanationStore.shared.explanation(for: storageKey)
    {
      guard !Task.isCancelled else { return }
      explanationStreamSource = nil
      explanationState = .loaded(stored)
      onExplained?()
      return
    }

    guard let explanationService else {
      explanationState = .failed(String(localized: "讲解服务暂不可用。"))
      return
    }

    let streamSource = GrowingMarkdownSource()
    explanationStreamSource = streamSource
    if let previousExplanation {
      explanationState = .regenerating(previousExplanation)
    } else {
      explanationState = .loading(isThinking: false)
    }
    var latestBody = ""
    var modelIdentifier = LLMGatewayConfig.chat.model

    do {
      for try await event in explanationService.streamExplanation(
        result: result,
        userKnowledgeStates: userKnowledgeStates,
        siteContext: siteContext
      ) {
        try Task.checkCancellation()
        switch event {
        case .thinking:
          if latestBody.isEmpty, previousExplanation == nil {
            explanationState = .loading(isThinking: true)
          }
        case .delta(let snapshot):
          let body = CultureChatService.displayBody(from: snapshot)
          guard !body.isEmpty else { continue }
          latestBody = body
          if previousExplanation == nil {
            explanationState = .streaming
            streamSource.yield(body)
          }
        case .finished(let model, let content):
          modelIdentifier = model
          let parsed = CultureChatService.parseAnswer(content)
          latestBody = parsed.body
          streamSource.finish()
          let explanation = PersonalizedExplanation(
            markdown: parsed.body,
            citations: parsed.citations,
            modelIdentifier: model
          )
          explanationState = .loaded(explanation)
          do {
            try await CultureExplanationStore.shared.save(explanation, for: storageKey)
          } catch {
            operationNotice = String(localized: "讲解已生成，但未能保存到本地。")
          }
        }
      }

      onExplained?()
    } catch {
      streamSource.finish()
      guard !Task.isCancelled else { return }
      if let previousExplanation {
        explanationState = .loaded(previousExplanation)
        operationNotice = String(localized: "重新生成失败，已保留原讲解。")
      } else if !latestBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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

  private var currentExplanation: PersonalizedExplanation? {
    switch explanationState {
    case .loaded(let explanation), .regenerating(let explanation),
      .partial(let explanation, _):
      explanation
    case .idle, .loading, .streaming, .failed:
      nil
    }
  }

  private func knowledgeContextSummary(
    for states: [UserKnowledgeStateContext]
  ) -> LocalizedStringKey {
    guard !states.isEmpty else {
      return "你的文化图谱暂无已有节点，将从必要背景讲起"
    }
    let deeperCount = states.filter { $0.level != KnowledgeLevel.contact.rawValue }.count
    if deeperCount > 0 {
      return "已结合文化图谱中 \(states.count) 个节点，其中 \(deeperCount) 个已理解或掌握"
    }
    return "已结合文化图谱中 \(states.count) 个接触过的节点补齐基础"
  }
}
