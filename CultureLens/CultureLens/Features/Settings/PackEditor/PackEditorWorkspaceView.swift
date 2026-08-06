import SwiftUI
import UniformTypeIdentifiers

/// Workspace for one draft: overview, entity lists, validation, and export.
struct PackEditorWorkspaceView: View {
  @Bindable var draft: KnowledgePackDraft
  @State private var store = KnowledgePackDraftStore.shared
  @State private var issues: [KnowledgePackIssue] = []
  @State private var exportDocument = PackZipDocument(data: Data())
  @State private var showExporter = false
  @State private var errorMessage: String?
  @State private var statusMessage: String?

  var body: some View {
    ZStack {
      CulturePageBackground()

      List {
        overviewSection
        elementsSection
        relationsSection
        introductionsSection
        themesSection
        localesSection
        validateSection
      }
      .scrollContentBackground(.hidden)
    }
    .cultureNavigationTitle(LocalizedStringKey(draft.displayName))
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("保存") { save() }
          .accessibilityIdentifier("packEditor.save")
        Button("导出") { exportPack() }
          .accessibilityIdentifier("packEditor.export")
      }
    }
    .fileExporter(
      isPresented: $showExporter,
      document: exportDocument,
      contentType: .zip,
      defaultFilename: KnowledgePackExporter.sanitizeDirectoryName(draft.version)
    ) { result in
      if case .failure(let error) = result {
        errorMessage = error.localizedDescription
      } else {
        statusMessage = "已导出 sidecar zip。"
      }
    }
    .alert("提示", isPresented: Binding(
      get: { errorMessage != nil || statusMessage != nil },
      set: { if !$0 { errorMessage = nil; statusMessage = nil } }
    )) {
      Button("好", role: .cancel) {
        errorMessage = nil
        statusMessage = nil
      }
    } message: {
      Text(errorMessage ?? statusMessage ?? "")
    }
    .onAppear { refreshIssues() }
  }

  private var overviewSection: some View {
    Section("概览") {
      TextField("显示名称", text: $draft.displayName)
      TextField("版本 version", text: $draft.version)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      TextField("源语言 source_language", text: $draft.sourceLanguage)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Text(
        "\(draft.elements.count) 元素 · \(draft.attractions.count) 景点 · \(draft.relations.count) 关系 · \(draft.introductions.count) 介绍 · \(draft.themes.count) 主题"
      )
      .font(.caption)
      .foregroundStyle(CultureTheme.inkSecondary)
    }
  }

  private var elementsSection: some View {
    Section {
      ForEach($draft.elements) { $element in
        NavigationLink {
          PackElementEditorView(element: $element) {
            draft.syncAttractionsFromElements()
            draft.markUpdated()
          }
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(element.name.isEmpty ? element.key : element.name)
              .foregroundStyle(CultureTheme.inkPrimary)
            Text("\(element.key) · \(element.contentRole.rawValue) · \(element.conceptKind.rawValue)")
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }
        }
      }
      .onDelete { draft.elements.remove(atOffsets: $0); draft.syncAttractionsFromElements() }

      Button {
        draft.elements.insert(
          EditableElement(key: "new-element", name: "新元素"),
          at: 0
        )
        draft.markUpdated()
      } label: {
        Label("添加元素", systemImage: "plus")
      }
    } header: {
      Text("元素")
    } footer: {
      Text("看点会自动同步到 attractions；介绍可用空行分段，图片用 ![图注](https://…)。")
    }
  }

  private var relationsSection: some View {
    Section("关系") {
      ForEach($draft.relations) { $relation in
        NavigationLink {
          PackRelationEditorView(relation: $relation, elementKeys: draft.elements.map(\.key))
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(relation.elementKey) → \(relation.relatedElementKey)")
              .foregroundStyle(CultureTheme.inkPrimary)
            Text(relation.kind.rawValue)
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }
        }
      }
      .onDelete { draft.relations.remove(atOffsets: $0) }

      Button {
        draft.relations.insert(EditableRelation(), at: 0)
        draft.markUpdated()
      } label: {
        Label("添加关系", systemImage: "plus")
      }
    }
  }

  private var introductionsSection: some View {
    Section("现场介绍") {
      ForEach($draft.introductions) { $intro in
        NavigationLink {
          PackIntroductionEditorView(introduction: $intro)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(intro.name.isEmpty ? intro.key : intro.name)
            Text(intro.key)
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }
        }
      }
      .onDelete { draft.introductions.remove(atOffsets: $0) }

      Button {
        draft.introductions.insert(EditableIntroduction(key: "new-intro", name: "新介绍"), at: 0)
        draft.markUpdated()
      } label: {
        Label("添加介绍", systemImage: "plus")
      }
    }
  }

  private var themesSection: some View {
    Section("主题") {
      ForEach($draft.themes) { $theme in
        NavigationLink {
          PackThemeEditorView(theme: $theme)
        } label: {
          Text(theme.name.isEmpty ? theme.key : theme.name)
        }
      }
      .onDelete { draft.themes.remove(atOffsets: $0) }

      Button {
        draft.themes.insert(EditableTheme(key: "new-theme", name: "新主题"), at: 0)
        draft.markUpdated()
      } label: {
        Label("添加主题", systemImage: "plus")
      }
    }
  }

  private var localesSection: some View {
    Section {
      ForEach($draft.englishLocales) { $locale in
        NavigationLink {
          PackLocaleEditorView(locale: $locale)
        } label: {
          Text(locale.name.isEmpty ? locale.key : locale.name)
        }
      }
      .onDelete { draft.englishLocales.remove(atOffsets: $0) }

      Button {
        draft.englishLocales.insert(
          EditableLocaleElement(key: "element-key", name: "", introductionText: ""),
          at: 0
        )
        draft.markUpdated()
      } label: {
        Label("添加英文覆盖", systemImage: "plus")
      }
    } header: {
      Text("英文 locales-en")
    }
  }

  private var validateSection: some View {
    Section {
      Button("重新校验") {
        refreshIssues()
      }
      if issues.isEmpty {
        Label("未发现问题", systemImage: "checkmark.seal")
          .foregroundStyle(.green)
      } else {
        ForEach(issues) { issue in
          Label {
            Text(issue.message)
              .font(.footnote)
          } icon: {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
              .foregroundStyle(issue.severity == .error ? CultureTheme.cinnabar : CultureTheme.antiqueGold)
          }
        }
      }
    } header: {
      Text("校验")
    }
  }

  private func refreshIssues() {
    issues = KnowledgePackValidator.validate(draft.buildPack())
  }

  private func save() {
    do {
      try store.save(draft)
      refreshIssues()
      statusMessage = "草稿已保存。"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func exportPack() {
    do {
      try store.save(draft)
      let pack = draft.buildPack()
      refreshIssues()
      if KnowledgePackValidator.hasErrors(pack) {
        errorMessage = "存在错误级问题，请先修复再导出。"
        return
      }
      let bundle = try KnowledgePackExporter.makeExportBundle(for: pack)
      let zip = try KnowledgePackExporter.zipData(for: bundle)
      exportDocument = PackZipDocument(data: zip)
      showExporter = true
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

/// FileDocument wrapper for exporting a sidecar zip.
struct PackZipDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.zip] }

  var data: Data

  init(data: Data) {
    self.data = data
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.data = data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}
