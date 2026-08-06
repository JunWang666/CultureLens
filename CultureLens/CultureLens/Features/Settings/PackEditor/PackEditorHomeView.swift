import SwiftUI
import UniformTypeIdentifiers

/// Home for knowledge-pack drafts: create, copy from bundled packs, import, open.
struct PackEditorHomeView: View {
  @State private var store = KnowledgePackDraftStore.shared
  @State private var errorMessage: String?
  @State private var showBundledPicker = false
  @State private var showImporter = false

  var body: some View {
    ZStack {
      CulturePageBackground()

      List {
        Section {
          Text("在设备上编辑知识包 sidecar，校验后导出为 zip，可拷回仓库的 Resources/KnowledgePack* 目录。")
            .font(CultureTypography.body(.footnote))
            .foregroundStyle(CultureTheme.inkSecondary)
            .listRowBackground(Color.clear)
        }

        Section("草稿") {
          if store.drafts.isEmpty {
            Text("还没有草稿。可新建空白包，或从内置包复制。")
              .font(CultureTypography.body(.subheadline))
              .foregroundStyle(CultureTheme.inkSecondary)
          } else {
            ForEach(store.drafts) { draft in
              NavigationLink(value: AppRoute.packEditorDraft(draft.id)) {
                draftRow(draft)
              }
            }
            .onDelete(perform: deleteDrafts)
          }
        }

        Section("操作") {
          Button {
            createBlank()
          } label: {
            Label("新建空白资源包", systemImage: "plus.square.on.square")
          }
          .accessibilityIdentifier("packEditor.newBlank")

          Button {
            showBundledPicker = true
          } label: {
            Label("从内置包复制", systemImage: "doc.on.doc")
          }
          .accessibilityIdentifier("packEditor.copyBundled")

          Button {
            showImporter = true
          } label: {
            Label("导入 JSON / 包目录", systemImage: "square.and.arrow.down")
          }
          .accessibilityIdentifier("packEditor.import")
        }
      }
      .scrollContentBackground(.hidden)
    }
    .cultureNavigationTitle("资源包编辑器")
    .alert("无法完成操作", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("好", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
    .sheet(isPresented: $showBundledPicker) {
      BundledPackPickerSheet { version in
        copyBundled(version)
      }
    }
    .fileImporter(
      isPresented: $showImporter,
      allowedContentTypes: [.json, .folder],
      allowsMultipleSelection: false
    ) { result in
      handleImport(result)
    }
  }

  private func draftRow(_ draft: KnowledgePackDraft) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(draft.displayName)
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)
      Text("\(draft.version) · \(draft.elements.count) 元素 · \(draft.relations.count) 关系")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .padding(.vertical, 4)
  }

  private func createBlank() {
    do {
      _ = try store.makeBlankDraft()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func copyBundled(_ version: String) {
    do {
      _ = try store.makeDraft(fromBundledVersion: version)
      showBundledPicker = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func deleteDrafts(at offsets: IndexSet) {
    for index in offsets {
      let draft = store.drafts[index]
      try? store.delete(draft)
    }
  }

  private func handleImport(_ result: Result<[URL], Error>) {
    do {
      guard let url = try result.get().first else { return }
      var isDirectory: ObjCBool = false
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
      if isDirectory.boolValue {
        _ = try store.importSidecarDirectory(from: url)
      } else {
        _ = try store.importMonolithJSON(from: url)
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct BundledPackPickerSheet: View {
  let onPick: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  private let summaries = KnowledgePackDraftStore.shared.bundledPackSummaries()

  var body: some View {
    NavigationStack {
      List(summaries) { summary in
        Button {
          onPick(summary.version)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(summary.version)
              .font(.headline)
              .foregroundStyle(CultureTheme.inkPrimary)
            Text(
              "\(summary.elementCount) 元素 · \(summary.attractionCount) 景点 · \(summary.relationCount) 关系"
            )
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
          }
        }
      }
      .cultureNavigationTitle("选择内置包")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    PackEditorHomeView()
  }
}
