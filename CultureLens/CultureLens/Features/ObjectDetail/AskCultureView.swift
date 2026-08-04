import Combine
import PhotosUI
import SwiftStreamingMarkdown
import SwiftUI
import UIKit

struct AskCultureView: View {
  let object: CultureObject?
  var rationale: String = ""
  var initialConversationID: UUID?

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @Environment(ChatHistoryStore.self) private var chatHistoryStore
  @StateObject private var model = AskCultureChatModel()
  @FocusState private var isComposerFocused: Bool
  @State private var composerTextHeight: CGFloat = 36
  @State private var selectedCitationKey: String?
  @State private var showHistorySheet = false
  @State private var showAttachMenu = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var isPickingPhoto = false

  private var isGeneralChat: Bool { object == nil }
  private let chatService = CultureChatService.live()

  var body: some View {
    ZStack {
      CulturePageBackground()

      VStack(spacing: 0) {
        messageList
        composer
      }
    }
    .cultureNavigationTitle(
      isGeneralChat ? "文化问答" : (object?.canonicalName ?? "继续追问"),
      subtitle: model.isSending
        ? (model.messages.last?.isThinking == true ? "正在思考…" : "正在流式回答…")
        : nil
    )
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          model.startNewConversation()
        } label: {
          Image(systemName: "square.and.pencil")
        }
        .accessibilityLabel("新对话")
        .disabled(model.isSending)

        Button {
          showHistorySheet = true
        } label: {
          Image(systemName: "clock")
        }
        .accessibilityLabel("历史对话")
      }
    }
    .onAppear {
      model.configure(
        object: object,
        rationale: rationale,
        chatService: chatService,
        knowledgeProgressStore: knowledgeProgressStore,
        chatHistoryStore: chatHistoryStore,
        initialConversationID: initialConversationID
      )
    }
    .environment(\.openURL, OpenURLAction { url in
      if let key = CultureCiteURL.elementKey(from: url) {
        selectedCitationKey = key
        return .handled
      }
      return .systemAction(url)
    })
    .navigationDestination(item: $selectedCitationKey) { key in
      if let concept = KnowledgeStore.shared?.cultureConcept(elementKey: key) {
        ConceptDetailView(concept: concept, elementKey: key)
      } else {
        ContentUnavailableView("知识节点暂不可用", systemImage: "externaldrive.badge.questionmark")
      }
    }
    .sheet(isPresented: $showHistorySheet) {
      ChatHistorySheet(
        objectID: object?.id,
        activeConversationID: model.conversationID,
        onSelect: { id in
          showHistorySheet = false
          model.loadConversation(id: id)
        },
        onDelete: { id in
          model.deleteConversation(id: id)
        },
        onNew: {
          showHistorySheet = false
          model.startNewConversation()
        }
      )
      .environment(chatHistoryStore)
    }
    .confirmationDialog("添加内容", isPresented: $showAttachMenu, titleVisibility: .visible) {
      Button("从相册选择图片") {
        isPickingPhoto = true
      }
      if model.pendingImageData != nil {
        Button("移除已选图片", role: .destructive) {
          model.clearPendingImage()
        }
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("上传现场照片，结合知识库追问。")
    }
    .photosPicker(
      isPresented: $isPickingPhoto,
      selection: $selectedPhoto,
      matching: .images,
      preferredItemEncoding: .current
    )
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task {
        await model.attachPhoto(item)
        selectedPhoto = nil
      }
    }
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if model.messages.isEmpty {
            emptyState
              .padding(.top, 8)
          }

          ForEach(model.messages) { message in
            chatBubble(message)
              .id(message.id)
          }

          if let errorMessage = model.errorMessage {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(CultureTheme.cinnabar)
              .padding(.horizontal, 4)
              .id("error")
          }

          Color.clear.frame(height: 8).id("bottom")
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: model.scrollTick) { _, _ in
        withAnimation(.easeOut(duration: 0.18)) {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(isGeneralChat ? "从知识库问起" : "继续追问这个对象")
        .font(.cultureSerif(.title2))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(
        isGeneralChat
          ? "回答会流式渲染，可上传图片，历史对话会自动保存。"
          : "围绕当前对象与图谱邻居提问；可附现场照片，内容约束在知识库片段内。"
      )
      .font(.subheadline)
      .foregroundStyle(CultureTheme.inkSecondary)

      FlowSuggestionRow(suggestions: model.suggestions) { text in
        model.draft = text
        isComposerFocused = true
        Task { await model.send() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  @ViewBuilder
  private func chatBubble(_ message: AskChatMessage) -> some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.role == .user { Spacer(minLength: 36) }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
        Group {
          switch message.role {
          case .user:
            VStack(alignment: .trailing, spacing: 8) {
              if let imageData = message.imageData {
                DataImageView(data: imageData)
                  .frame(width: 168, height: 168)
                  .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                  .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                      .stroke(CultureTheme.hairline, lineWidth: 1)
                  }
              }
              if !message.text.isEmpty {
                Text(message.text)
                  .font(.body)
                  .foregroundStyle(.white)
                  .multilineTextAlignment(.leading)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 10)
                  .background(
                    CultureTheme.cinnabar,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                  )
              }
            }
          case .assistant:
            assistantContent(message)
              .padding(.horizontal, 14)
              .padding(.vertical, 10)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                CultureTheme.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .stroke(CultureTheme.hairline, lineWidth: 1)
              }
          }
        }

        if message.role == .assistant, !message.citations.isEmpty, !message.isStreaming {
          KnowledgeCitationCardsView(citations: message.citations) { citation in
            selectedCitationKey = citation.key
          }
        }
      }

      if message.role == .assistant { Spacer(minLength: 36) }
    }
  }

  @ViewBuilder
  private func assistantContent(_ message: AskChatMessage) -> some View {
    if message.isStreaming, message.isThinking {
      ThinkingStatusView()
    } else if let source = message.streamSource, message.isStreaming {
      // Stable identity: do not recreate this view while tokens arrive.
      StreamedMarkdownView(source: source, config: Self.markdownConfig)
        .id("stream-\(message.id)")
    } else if !message.text.isEmpty {
      MarkdownView(text: message.text, config: Self.markdownConfig)
    } else {
      HStack(spacing: 8) {
        ProgressView()
        Text("正在组织回答…")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
      }
    }
  }

  /// ChatGPT-style pill composer: + | field | microphone | voice/send.
  private var composer: some View {
    VStack(spacing: 0) {
      if let pending = model.pendingImageData {
        HStack(spacing: 12) {
          DataImageView(data: pending)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CultureTheme.hairline, lineWidth: 1)
            }

          VStack(alignment: .leading, spacing: 2) {
            Text("已附图片")
              .font(.subheadline.weight(.medium))
              .foregroundStyle(CultureTheme.inkPrimary)
            Text("发送时一并交给知识库问答")
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }

          Spacer(minLength: 0)

          Button {
            model.clearPendingImage()
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.title3)
              .foregroundStyle(CultureTheme.inkSecondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("移除图片")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
      }

      HStack(alignment: .bottom, spacing: 8) {
        Button {
          showAttachMenu = true
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 21, weight: .regular))
            .foregroundStyle(CultureTheme.inkPrimary)
            .frame(width: 34, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chatService == nil || model.isSending)
        .accessibilityLabel("添加图片")

        ChatComposerTextView(
          text: $model.draft,
          isFocused: Binding(
            get: { isComposerFocused },
            set: { isComposerFocused = $0 }
          ),
          measuredHeight: $composerTextHeight,
          placeholder: isGeneralChat ? "询问 CultureLens" : "继续追问…",
          isEnabled: chatService != nil && !model.isSending,
          onSend: {
            Task { await model.send() }
          }
        )
        .frame(height: composerTextHeight)

        Button {
          isComposerFocused = true
        } label: {
          Image(systemName: "mic")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(CultureTheme.inkPrimary)
            .frame(width: 34, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chatService == nil || model.isSending)
        .accessibilityLabel("语音输入")
        .accessibilityHint("打开输入框后可使用系统听写")

        Button {
          if model.canSend {
            Task { await model.send() }
          } else {
            isComposerFocused = true
          }
        } label: {
          ZStack {
            Circle()
              .fill(Color(red: 0.02, green: 0.47, blue: 0.98))

            if model.canSend {
              Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            } else {
              ChatVoiceWaveformIcon()
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
          }
          .frame(width: 36, height: 36)
          .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(chatService == nil || model.isSending)
        .accessibilityLabel(model.canSend ? "发送" : "语音对话")
      }
      .animation(.easeOut(duration: 0.16), value: model.canSend)
      .padding(.leading, 8)
      .padding(.trailing, 7)
      .padding(.vertical, 6)
      .background(
        CultureTheme.surface,
        in: RoundedRectangle(cornerRadius: 24, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(CultureTheme.inkPrimary.opacity(0.16), lineWidth: 1)
      }
      .padding(.horizontal, 12)
      .padding(.top, 8)
      .padding(.bottom, 10)
    }
    .background(.ultraThinMaterial)
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: true)
  }
}

private struct ChatVoiceWaveformIcon: View {
  private let barHeights: [CGFloat] = [10, 17, 24, 17, 10]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
        Capsule()
          .fill(.white)
          .frame(width: 2.5, height: height)
      }
    }
    .accessibilityHidden(true)
  }
}

// MARK: - History sheet

private struct ChatHistorySheet: View {
  let objectID: UUID?
  let activeConversationID: UUID
  let onSelect: (UUID) -> Void
  let onDelete: (UUID) -> Void
  let onNew: () -> Void

  @Environment(ChatHistoryStore.self) private var chatHistoryStore
  @Environment(\.dismiss) private var dismiss
  @State private var refreshID = UUID()

  private var records: [ChatConversationRecord] {
    _ = refreshID
    return chatHistoryStore.conversations(objectID: objectID)
  }

  var body: some View {
    NavigationStack {
      Group {
        if records.isEmpty {
          ContentUnavailableView(
            "暂无历史对话",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("发送第一条消息后，对话会出现在这里。")
          )
        } else {
          List {
            ForEach(records, id: \.conversationID) { record in
              Button {
                onSelect(record.conversationID)
              } label: {
                HStack(alignment: .top, spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                      .font(.body.weight(.medium))
                      .foregroundStyle(CultureTheme.inkPrimary)
                      .lineLimit(2)
                    Text(record.previewText)
                      .font(.caption)
                      .foregroundStyle(CultureTheme.inkSecondary)
                      .lineLimit(1)
                    Text(record.updatedAt, format: .dateTime.month().day().hour().minute())
                      .font(.caption2)
                      .foregroundStyle(CultureTheme.inkSecondary.opacity(0.8))
                  }
                  Spacer(minLength: 0)
                  if record.conversationID == activeConversationID {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(CultureTheme.cinnabar)
                  }
                }
              }
              .buttonStyle(.plain)
            }
            .onDelete { indexSet in
              for index in indexSet {
                onDelete(records[index].conversationID)
              }
              refreshID = UUID()
            }
          }
          .listStyle(.plain)
        }
      }
      .navigationTitle("历史对话")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("关闭") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
          Button("新对话", action: onNew)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

// MARK: - Model

@MainActor
final class AskCultureChatModel: ObservableObject {
  @Published var messages: [AskChatMessage] = []
  @Published var draft = ""
  @Published var isSending = false
  @Published var errorMessage: String?
  @Published var scrollTick = 0
  @Published var pendingImageData: Data?
  @Published private(set) var conversationID = UUID()

  private var object: CultureObject?
  private var rationale = ""
  private var chatService: CultureChatService?
  private weak var knowledgeProgressStore: KnowledgeProgressStore?
  private weak var chatHistoryStore: ChatHistoryStore?
  private var didConfigure = false
  private var streamTask: Task<Void, Never>?

  var suggestions: [String] {
    if object == nil {
      return [
        "西湖十景是怎样被命名的？",
        "三潭映月和苏轼有什么关系？",
        "我已经了解的节点还能怎样串联？",
      ]
    }
    return [
      "它为什么会形成这样的结构？",
      "在不同地区有什么变化？",
      "我还能在哪里看到相似对象？",
    ]
  }

  var canSend: Bool {
    guard chatService != nil, !isSending else { return false }
    let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return hasText || pendingImageData != nil
  }

  func configure(
    object: CultureObject?,
    rationale: String,
    chatService: CultureChatService?,
    knowledgeProgressStore: KnowledgeProgressStore,
    chatHistoryStore: ChatHistoryStore,
    initialConversationID: UUID?
  ) {
    self.object = object
    self.rationale = rationale
    self.chatService = chatService
    self.knowledgeProgressStore = knowledgeProgressStore
    self.chatHistoryStore = chatHistoryStore
    guard !didConfigure else { return }
    didConfigure = true
    if let initialConversationID {
      loadConversation(id: initialConversationID)
    }
  }

  func startNewConversation() {
    streamTask?.cancel()
    conversationID = UUID()
    messages = []
    draft = ""
    pendingImageData = nil
    errorMessage = nil
    isSending = false
    bumpScroll()
  }

  func loadConversation(id: UUID) {
    guard let record = chatHistoryStore?.conversation(id: id) else { return }
    streamTask?.cancel()
    isSending = false
    errorMessage = nil
    pendingImageData = nil
    draft = ""
    conversationID = record.conversationID
    messages = record.messages.map { persisted in
      AskChatMessage(
        id: persisted.id,
        role: persisted.role == .user ? .user : .assistant,
        text: persisted.text,
        citations: persisted.citations.map(\.asKnowledgeCitation),
        imageRelativePath: persisted.imageRelativePath,
        imageData: ChatMediaStoreSync.data(for: persisted.imageRelativePath)
      )
    }
    bumpScroll()
  }

  func deleteConversation(id: UUID) {
    chatHistoryStore?.delete(id: id)
    if conversationID == id {
      startNewConversation()
    }
  }

  func clearPendingImage() {
    pendingImageData = nil
  }

  func attachPhoto(_ item: PhotosPickerItem) async {
    do {
      guard let raw = try await item.loadTransferable(type: Data.self) else {
        throw ImagePreprocessorError.unreadableImage
      }
      let jpeg = try ImagePreprocessor.normalizedJPEG(from: raw)
      pendingImageData = jpeg
      errorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func send() async {
    guard let chatService, let knowledgeProgressStore else {
      errorMessage = "追问服务暂不可用。"
      return
    }
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let imageJPEG = pendingImageData
    guard !trimmed.isEmpty || imageJPEG != nil else { return }
    guard !isSending else { return }

    errorMessage = nil
    isSending = true
    draft = ""
    pendingImageData = nil

    let history = messages.compactMap { message -> ChatTurn? in
      var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if message.imageRelativePath != nil || message.imageData != nil {
        if text.isEmpty {
          text = "（用户上传了一张图片）"
        } else if !text.contains("图片") {
          text += "（附图片）"
        }
      }
      guard !text.isEmpty else { return nil }
      return ChatTurn(
        role: message.role == .user ? .user : .assistant,
        content: text
      )
    }

    var imageRelativePath: String?
    if let imageJPEG {
      imageRelativePath = try? await ChatMediaStore.shared.saveJPEG(imageJPEG)
    }

    let userMessage = AskChatMessage(
      role: .user,
      text: trimmed,
      imageRelativePath: imageRelativePath,
      imageData: imageJPEG
    )
    messages.append(userMessage)
    bumpScroll()

    let source = GrowingMarkdownSource()
    let assistantID = UUID()
    messages.append(
      AskChatMessage(
        id: assistantID,
        role: .assistant,
        text: "",
        isStreaming: true,
        isThinking: false,
        streamSource: source
      )
    )
    bumpScroll()

    do {
      var lastScrollCount = 0
      var hasContent = false
      for try await event in chatService.streamAsk(
        object: object,
        rationale: rationale,
        userKnowledgeStates: knowledgeProgressStore.userKnowledgeStates(
          knowledgeStore: KnowledgeStore.shared
        ),
        history: history,
        question: trimmed,
        imageJPEG: imageJPEG
      ) {
        switch event {
        case .thinking:
          updateAssistant(id: assistantID) { message in
            message.isThinking = true
          }
          bumpScroll()
        case .delta(let snapshot):
          // Only push into the markdown source — mutating message.text
          // would recreate StreamedMarkdownView and kill the stream.
          if !hasContent {
            hasContent = true
            updateAssistant(id: assistantID) { message in
              message.isThinking = false
            }
          }
          let body = CultureChatService.displayBody(from: snapshot)
          source.yield(body.isEmpty ? snapshot : body)
          if snapshot.count - lastScrollCount > 24 {
            lastScrollCount = snapshot.count
            bumpScroll()
          }
        case .finished(_, let content):
          let parsed = CultureChatService.parseAnswer(content)
          source.yield(parsed.body)
          source.finish()
          updateAssistant(id: assistantID) { message in
            message.text = parsed.body
            message.isStreaming = false
            message.isThinking = false
            message.streamSource = nil
            message.citations = parsed.citations
          }
          bumpScroll()
        }
      }

      persistConversation()

      if let object, let key = object.culturalElementKey {
        let current = knowledgeProgressStore.level(for: object.id, elementKey: key)
        if current == nil || current == .contact {
          knowledgeProgressStore.setLevel(
            .understand,
            for: object.id,
            source: .ask,
            elementKey: key
          )
        }
      }
    } catch {
      source.finish()
      if let index = messages.firstIndex(where: { $0.id == assistantID }) {
        if messages[index].text.isEmpty {
          messages.remove(at: index)
        } else {
          messages[index].isStreaming = false
          messages[index].streamSource = nil
          persistConversation()
        }
      }
      errorMessage = error.localizedDescription
    }
    isSending = false
  }

  private func persistConversation() {
    let persisted = messages.compactMap { message -> PersistedChatMessage? in
      guard !message.isStreaming else { return nil }
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty, message.imageRelativePath == nil { return nil }
      return PersistedChatMessage(
        id: message.id,
        role: message.role == .user ? .user : .assistant,
        text: message.text,
        imageRelativePath: message.imageRelativePath,
        citations: message.citations.map(PersistedKnowledgeCitation.init)
      )
    }
    guard !persisted.isEmpty else { return }
    chatHistoryStore?.upsert(
      conversationID: conversationID,
      object: object,
      messages: persisted
    )
  }

  private func updateAssistant(id: UUID, mutate: (inout AskChatMessage) -> Void) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    mutate(&messages[index])
  }

  private func bumpScroll() {
    scrollTick &+= 1
  }
}

/// Sync helpers for reading chat media off the actor from the main thread.
enum ChatMediaStoreSync {
  static func data(for relativePath: String?) -> Data? {
    guard let relativePath else { return nil }
    let fileManager = FileManager.default
    guard
      let applicationSupport = try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else { return nil }
    let url = applicationSupport
      .appending(path: "CultureLens", directoryHint: .isDirectory)
      .appending(path: "Chats", directoryHint: .isDirectory)
      .appending(path: relativePath)
    return try? Data(contentsOf: url)
  }
}

struct AskChatMessage: Identifiable, Equatable {
  enum Role: Equatable {
    case user
    case assistant
  }

  let id: UUID
  let role: Role
  var text: String
  var isStreaming: Bool
  var isThinking: Bool
  var streamSource: GrowingMarkdownSource?
  var citations: [KnowledgeCitation]
  var imageRelativePath: String?
  var imageData: Data?

  init(
    id: UUID = UUID(),
    role: Role,
    text: String,
    isStreaming: Bool = false,
    isThinking: Bool = false,
    streamSource: GrowingMarkdownSource? = nil,
    citations: [KnowledgeCitation] = [],
    imageRelativePath: String? = nil,
    imageData: Data? = nil
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.isStreaming = isStreaming
    self.isThinking = isThinking
    self.streamSource = streamSource
    self.citations = citations
    self.imageRelativePath = imageRelativePath
    self.imageData = imageData
  }

  static func == (lhs: AskChatMessage, rhs: AskChatMessage) -> Bool {
    // Ignore text while streaming so token updates don't rebuild the bubble.
    lhs.id == rhs.id
      && lhs.role == rhs.role
      && lhs.isStreaming == rhs.isStreaming
      && lhs.isThinking == rhs.isThinking
      && (lhs.isStreaming || lhs.text == rhs.text)
      && lhs.citations == rhs.citations
      && (lhs.streamSource == nil) == (rhs.streamSource == nil)
      && lhs.imageRelativePath == rhs.imageRelativePath
      && (lhs.imageData == nil) == (rhs.imageData == nil)
  }
}

/// Animated “正在思考…” while the model streams reasoning_content.
private struct ThinkingStatusView: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.35, paused: false)) { context in
      let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 4
      let dots = String(repeating: ".", count: phase)
      HStack(spacing: 10) {
        ThinkingPulseDots()
        Text("正在思考\(dots)")
          .font(.subheadline)
          .foregroundStyle(CultureTheme.inkSecondary)
          .monospacedDigit()
          .animation(nil, value: phase)
      }
      .accessibilityLabel("正在思考")
    }
  }
}

private struct ThinkingPulseDots: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.28, paused: false)) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          let wave = (sin(t * 5.2 + Double(index) * 0.85) + 1) / 2
          Circle()
            .fill(CultureTheme.cinnabar.opacity(0.35 + 0.55 * wave))
            .frame(width: 6, height: 6)
            .scaleEffect(0.75 + 0.45 * wave)
        }
      }
    }
  }
}

/// UIKit field so Return/发送 works with Chinese IME (confirm candidate ≠ send).
private struct ChatComposerTextView: UIViewRepresentable {
  @Binding var text: String
  @Binding var isFocused: Bool
  @Binding var measuredHeight: CGFloat
  var placeholder: String
  var isEnabled: Bool
  var onSend: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.delegate = context.coordinator
    view.backgroundColor = .clear
    view.textContainerInset = UIEdgeInsets(top: 6, left: 2, bottom: 6, right: 2)
    view.textContainer.lineFragmentPadding = 0
    view.font = UIFont.preferredFont(forTextStyle: .body)
    view.adjustsFontForContentSizeCategory = true
    view.returnKeyType = .send
    view.enablesReturnKeyAutomatically = true
    view.autocorrectionType = .yes
    view.spellCheckingType = .no
    view.isScrollEnabled = false
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    view.setContentHuggingPriority(.required, for: .vertical)
    context.coordinator.placeholderLabel.text = placeholder
    context.coordinator.placeholderLabel.font = view.font
    context.coordinator.placeholderLabel.textColor = UIColor.placeholderText
    context.coordinator.placeholderLabel.numberOfLines = 1
    view.addSubview(context.coordinator.placeholderLabel)
    context.coordinator.placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      context.coordinator.placeholderLabel.leadingAnchor.constraint(
        equalTo: view.leadingAnchor,
        constant: 2
      ),
      context.coordinator.placeholderLabel.topAnchor.constraint(
        equalTo: view.topAnchor,
        constant: 6
      ),
      context.coordinator.placeholderLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -2
      ),
    ])
    context.coordinator.scheduleHeightUpdate(for: view)
    return view
  }

  func updateUIView(_ uiView: UITextView, context: Context) {
    context.coordinator.parent = self
    if uiView.text != text {
      uiView.text = text
    }
    uiView.isEditable = isEnabled
    uiView.isUserInteractionEnabled = isEnabled
    context.coordinator.placeholderLabel.text = placeholder
    context.coordinator.placeholderLabel.isHidden = !text.isEmpty
    context.coordinator.syncFocus(uiView)
    context.coordinator.scheduleHeightUpdate(for: uiView)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: ChatComposerTextView
    let placeholderLabel = UILabel()

    init(_ parent: ChatComposerTextView) {
      self.parent = parent
    }

    func syncFocus(_ view: UITextView) {
      if parent.isFocused {
        if !view.isFirstResponder { view.becomeFirstResponder() }
      } else if view.isFirstResponder {
        view.resignFirstResponder()
      }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
      parent.isFocused = true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      parent.isFocused = false
    }

    func textViewDidChange(_ textView: UITextView) {
      parent.text = textView.text ?? ""
      placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
      updateHeight(for: textView)
    }

    func scheduleHeightUpdate(for textView: UITextView) {
      DispatchQueue.main.async { [weak self, weak textView] in
        guard let self, let textView else { return }
        self.updateHeight(for: textView)
      }
    }

    private func updateHeight(for textView: UITextView) {
      guard textView.bounds.width > 0 else { return }
      textView.isScrollEnabled = false
      let contentHeight = textView.sizeThatFits(
        CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
      ).height
      let nextHeight = min(max(contentHeight, 36), 96)
      textView.isScrollEnabled = contentHeight > 96

      if abs(parent.measuredHeight - nextHeight) > 0.5 {
        parent.measuredHeight = nextHeight
      }
    }

    func textView(
      _ textView: UITextView,
      shouldChangeTextIn range: NSRange,
      replacementText text: String
    ) -> Bool {
      // Return / 发送: send when not composing IME candidates.
      if text == "\n" {
        if textView.markedTextRange == nil {
          parent.onSend()
        }
        return false
      }
      return true
    }
  }
}

private struct FlowSuggestionRow: View {
  let suggestions: [String]
  let onTap: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(suggestions, id: \.self) { suggestion in
        Button {
          onTap(suggestion)
        } label: {
          Text(suggestion)
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              CultureTheme.canvas.opacity(0.7),
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
      }
    }
  }
}

#Preview("对象追问") {
  NavigationStack {
    AskCultureView(object: SampleCultureData.featured)
  }
  .environment(KnowledgeProgressStore())
  .environment(ChatHistoryStore())
}

#Preview("首页问答") {
  NavigationStack {
    AskCultureView(object: nil)
  }
  .environment(KnowledgeProgressStore())
  .environment(ChatHistoryStore())
}
