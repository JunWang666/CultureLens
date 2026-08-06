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
  private let explanationService = CultureExplanationService.live()

  var body: some View {
    if !isDemo {
      content
        .task(id: result.id) {
          await loadExplanation()
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

  @MainActor
  private func loadExplanation() async {
    explanationStreamSource?.finish()

    let userKnowledgeStates = knowledgeProgressStore.userKnowledgeStates(
      knowledgeStore: KnowledgeStore.shared
    )
    knowledgeContextSummary = knowledgeContextSummary(for: userKnowledgeStates)

    guard let explanationService else {
      explanationState = .failed(String(localized: "讲解服务暂不可用。"))
      return
    }

    let streamSource = GrowingMarkdownSource()
    explanationStreamSource = streamSource
    explanationState = .loading(isThinking: false)
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

      onExplained?()
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
