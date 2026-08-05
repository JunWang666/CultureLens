import Combine
import PhotosUI
import SwiftStreamingMarkdown
import SwiftUI

struct AskCultureView: View {
  let object: CultureObject?
  var rationale: String = ""
  var initialConversationID: UUID?

  @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
  @Environment(ChatHistoryStore.self) private var chatHistoryStore
  @StateObject private var model = AskCultureChatModel()
  @FocusState private var isComposerFocused: Bool
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
      isGeneralChat
        ? "文化问答"
        : (object.map { LocalizedStringKey($0.canonicalName) } ?? "继续追问"),
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
      if let element = KnowledgeStore.shared?.element(key: key) {
        ScanResultView(knowledgeObject: CultureObject(knowledgeElement: element))
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
      Text(isGeneralChat ? LocalizedStringKey("好奇什么，直接问") : "继续追问这个对象")
        .font(.cultureSerif(.title2))
        .foregroundStyle(CultureTheme.inkPrimary)

      Text(
        isGeneralChat
          ? LocalizedStringKey("从知识库与你的文化图谱里找答案，也可以附一张现场照片。")
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
    .frame(maxWidth: 560, alignment: .leading)
    .padding(18)
    .background(
      CultureTheme.surface,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
    .frame(maxWidth: .infinity, alignment: .center)
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
            if assistantHasVisibleBody(message) {
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
        }

        if message.role == .assistant,
          !message.citations.existingInKnowledgeBase().isEmpty,
          !message.isStreaming
        {
          KnowledgeCitationCardsView(citations: message.citations) { citation in
            selectedCitationKey = citation.key
          }
        }
      }

      if message.role == .assistant { Spacer(minLength: 36) }
    }
  }

  private func assistantHasVisibleBody(_ message: AskChatMessage) -> Bool {
    if message.isStreaming { return true }
    if !message.text.isEmpty { return true }
    // Finished with citations only — skip the empty "正在组织回答…" bubble.
    return message.citations.existingInKnowledgeBase().isEmpty
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
        HStack {
          DataImageView(data: pending)
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CultureTheme.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
              Button {
                model.clearPendingImage()
              } label: {
                Image(systemName: "xmark")
                  .font(.system(size: 11, weight: .bold))
                  .foregroundStyle(CultureTheme.inkPrimary)
                  .frame(width: 24, height: 24)
                  .background(.regularMaterial, in: Circle())
              }
              .buttonStyle(.plain)
              .accessibilityLabel("移除图片")
              .offset(x: 8, y: -8)
            }

          Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
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
        .popover(
          isPresented: $showAttachMenu,
          attachmentAnchor: .rect(.bounds),
          arrowEdge: .bottom
        ) {
          VStack(alignment: .leading, spacing: 4) {
            Button {
              showAttachMenu = false
              Task { @MainActor in
                await Task.yield()
                isPickingPhoto = true
              }
            } label: {
              Label("从相册选择", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)

            if model.pendingImageData != nil {
              Divider()

              Button(role: .destructive) {
                model.clearPendingImage()
                showAttachMenu = false
              } label: {
                Label("移除已选图片", systemImage: "trash")
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .padding(10)
            }
          }
          .font(.body)
          .frame(width: 210)
          .padding(6)
          .presentationCompactAdaptation(.popover)
        }

        TextField(
          isGeneralChat ? "询问 CultureLens" : "继续追问…",
          text: $model.draft,
          axis: .vertical
        )
        .focused($isComposerFocused)
        .font(.body)
        .textFieldStyle(.plain)
        .lineLimit(1...4)
        .submitLabel(.send)
        .onSubmit {
          guard model.canSend else { return }
          Task { await model.send() }
        }
        .frame(minHeight: 36)
        .disabled(chatService == nil || model.isSending)

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
        .accessibilityLabel(model.canSend ? LocalizedStringKey("发送") : "语音对话")
      }
      .animation(.easeOut(duration: 0.16), value: model.canSend)
      .padding(.leading, 8)
      .padding(.trailing, 7)
      .padding(.vertical, 6)
    }
    .modifier(ChatComposerGlassStyle())
    .animation(.easeOut(duration: 0.2), value: model.pendingImageData != nil)
    .padding(.horizontal, 12)
    .padding(.top, 8)
    .padding(.bottom, 10)
  }

  private static var markdownConfig: MarkdownRenderConfig {
    .default.withShouldAnimateText(value: true)
  }
}

private struct ChatComposerGlassStyle: ViewModifier {
  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    } else {
      content
        .background(
          .ultraThinMaterial,
          in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(CultureTheme.inkPrimary.opacity(0.14), lineWidth: 1)
        }
    }
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

  /// Suggestions double as the message sent on tap, so resolve against the
  /// app language (not the device locale) like the chat service does.
  var suggestions: [String] {
    let isEnglish = AppLanguageStore.currentLanguage() == .english
    if object == nil {
      if isEnglish {
        return [
          "How were the Ten Scenes of West Lake named?",
          "What connects Three Pools Mirroring the Moon and Su Shi?",
          "How else can the nodes I already know be connected?",
        ]
      }
      return [
        "西湖十景是怎样被命名的？",
        "三潭映月和苏轼有什么关系？",
        "我已经了解的节点还能怎样串联？",
      ]
    }
    if isEnglish {
      return [
        "Why did it develop this structure?",
        "How does it vary across regions?",
        "Where else can I see similar objects?",
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
      errorMessage = String(localized: "追问服务暂不可用。")
      return
    }
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let imageJPEG = pendingImageData
    guard !trimmed.isEmpty || imageJPEG != nil else { return }
    guard !isSending else { return }

    errorMessage = nil
    isSending = true
    defer { isSending = false }
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
          // Prefer parsed body; if the model only emitted the citation
          // section, keep whatever the stream already displayed.
          let body =
            parsed.body.isEmpty
            ? CultureChatService.displayBody(from: source.latest.isEmpty ? content : source.latest)
            : parsed.body
          source.yield(body)
          source.finish()
          updateAssistant(id: assistantID) { message in
            message.text = body
            message.isStreaming = false
            message.isThinking = false
            message.streamSource = nil
            message.citations = parsed.citations
          }
          bumpScroll()
        }
      }

      // Clear sending state before SwiftData work so a save failure / debugger
      // breakpoint cannot leave the subtitle stuck on「正在流式回答…」.
      isSending = false
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
        if messages[index].text.isEmpty, messages[index].citations.isEmpty {
          messages.remove(at: index)
        } else {
          messages[index].isStreaming = false
          messages[index].streamSource = nil
          isSending = false
          persistConversation()
        }
      }
      errorMessage = error.localizedDescription
    }
  }

  private func persistConversation() {
    let persisted = messages.compactMap { message -> PersistedChatMessage? in
      guard !message.isStreaming else { return nil }
      let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
      // Keep assistant turns that only have citation cards.
      if text.isEmpty, message.imageRelativePath == nil, message.citations.isEmpty {
        return nil
      }
      return PersistedChatMessage(
        id: message.id,
        role: message.role == .user ? .user : .assistant,
        text: message.text,
        imageRelativePath: message.imageRelativePath,
        citations: message.citations.map(PersistedKnowledgeCitation.init)
      )
    }
    guard !persisted.isEmpty else { return }
    guard let chatHistoryStore else { return }
    do {
      try chatHistoryStore.upsert(
        conversationID: conversationID,
        object: object,
        messages: persisted
      )
    } catch {
      errorMessage = String(localized: "对话保存失败：\(error.localizedDescription)")
    }
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
