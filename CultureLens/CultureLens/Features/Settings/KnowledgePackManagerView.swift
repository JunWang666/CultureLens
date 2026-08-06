import SwiftUI

/// Lists the unified knowledge ODR pack and the image pack, and lets users
/// retry a missing initial-install resource.
struct KnowledgePackManagerView: View {
  @State private var resources: [KnowledgePackResource] = []
  @State private var imagePack: ImagePackResource?
  @State private var isLoading = true
  @State private var downloadingIDs = Set<String>()
  @State private var releasingIDs = Set<String>()
  @State private var errorMessage: String?
  @State private var packPendingRelease: ReleaseTarget?

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
          introduction

          if isLoading && resources.isEmpty && imagePack == nil {
            ProgressView("正在检查资源包…")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 48)
          } else {
            VStack(alignment: .leading, spacing: 16) {
              ForEach(resources) { resource in
                resourceCard(resource)
              }
              if let imagePack {
                imagePackCard(imagePack)
              }
            }
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(CultureTypography.body(.footnote))
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.horizontal, 4)
          }

          MagazineFooterOrnament()
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
      .refreshable { await refresh() }
    }
    .cultureNavigationTitle("资源包管理")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          Task { await refresh() }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .disabled(isLoading)
        .accessibilityLabel("刷新资源包状态")
        .accessibilityIdentifier("knowledgePacks.refresh")
      }
    }
    .task { await refresh() }
    .confirmationDialog(
      releaseDialogTitle,
      isPresented: Binding(
        get: { packPendingRelease != nil },
        set: { if !$0 { packPendingRelease = nil } }
      ),
      titleVisibility: .visible
    ) {
      Button("卸载", role: .destructive) {
        guard let target = packPendingRelease else { return }
        packPendingRelease = nil
        Task { await release(target) }
      }
      Button("取消", role: .cancel) {
        packPendingRelease = nil
      }
    } message: {
      Text(releaseDialogMessage)
    }
  }

  private var introduction: some View {
    MagazinePageHeader(
      eyebrow: "PACKS",
      title: "知识与图片资源包",
      message: "知识包与图片包首次安装时默认随 App 交付；若系统清理了按需资源，可在这里重新下载。图片包会拦截对应的远程图片请求，优先读本地文件。"
    )
  }

  private var releaseDialogTitle: LocalizedStringKey {
    switch packPendingRelease {
    case .knowledge: "卸载知识资源包？"
    case .images: "卸载图片资源包？"
    case nil: "卸载资源包？"
    }
  }

  private var releaseDialogMessage: LocalizedStringKey {
    "会结束对本包的访问声明。侧载或嵌入构建里资源仍留在 App 内，无法真正删盘；App Store 安装下系统稍后可能回收空间。"
  }

  private func resourceCard(_ resource: KnowledgePackResource) -> some View {
    packPanel {
      HStack(alignment: .top, spacing: 14) {
        packIcon(resource.directory.systemImage)

        VStack(alignment: .leading, spacing: 4) {
          Text(resource.directory.title)
            .font(CultureTypography.title(.headline))
            .foregroundStyle(CultureTheme.inkPrimary)
          if let version = resource.version {
            (Text("版本") + Text(verbatim: " \(version)"))
              .font(.caption.monospaced())
              .foregroundStyle(CultureTheme.inkSecondary)
              .accessibilityIdentifier("knowledgePacks.version.\(resource.id)")
          }
          Text(verbatim: resource.directory.odrTag)
            .font(.caption2.monospaced())
            .foregroundStyle(CultureTheme.inkSecondary.opacity(0.75))
        }

        Spacer(minLength: 8)
        statusBadge(resource.availability)
      }

      if resource.availability == .available {
        HStack(spacing: 0) {
          metric(value: resource.elementCount, label: "知识节点")
          Rectangle().fill(CultureTheme.hairline).frame(width: 1, height: 30)
          metric(value: resource.attractionCount, label: "景点")
          Rectangle().fill(CultureTheme.hairline).frame(width: 1, height: 30)
          metric(value: resource.relationCount, label: "关系")
        }
        .padding(.vertical, 4)
      } else {
        Text(resource.availability == .notDownloaded ? "此资源包当前不在设备上。" : "资源包文件无法读取，请重试。")
          .font(CultureTypography.body(.footnote))
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      packActions(
        id: resource.id,
        availability: resource.availability,
        onDownload: { Task { await download(resource) } },
        onRelease: { packPendingRelease = .knowledge(resource) }
      )
    }
  }

  private func imagePackCard(_ resource: ImagePackResource) -> some View {
    packPanel {
      HStack(alignment: .top, spacing: 14) {
        packIcon("photo.on.rectangle.angled")

        VStack(alignment: .leading, spacing: 4) {
          Text("知识配图")
            .font(CultureTypography.title(.headline))
            .foregroundStyle(CultureTheme.inkPrimary)
          Text("按需资源 tag")
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
          Text(verbatim: ImagePackLoader.odrTag)
            .font(.caption2.monospaced())
            .foregroundStyle(CultureTheme.inkSecondary.opacity(0.75))
        }

        Spacer(minLength: 8)
        statusBadge(resource.availability)
      }

      if resource.availability == .available {
        HStack(spacing: 0) {
          metric(value: resource.imageCount, label: "配图")
        }
        .padding(.vertical, 4)
      } else {
        Text(resource.availability == .notDownloaded ? "此图片包当前不在设备上。" : "图片包文件无法读取，请重试。")
          .font(CultureTypography.body(.footnote))
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      packActions(
        id: resource.id,
        availability: resource.availability,
        onDownload: { Task { await downloadImagePack(resource) } },
        onRelease: { packPendingRelease = .images(resource) }
      )
    }
  }

  private func packPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      content()
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CultureTheme.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(CultureTheme.hairline, lineWidth: 1)
    }
  }

  private func packIcon(_ systemImage: String) -> some View {
    Image(systemName: systemImage)
      .font(.title3)
      .foregroundStyle(CultureTheme.antiqueGold)
      .frame(width: 34, height: 34)
      .background(CultureTheme.antiqueGold.opacity(0.12), in: Circle())
      .accessibilityHidden(true)
  }

  private func packActions(
    id: String,
    availability: KnowledgePackResource.Availability,
    onDownload: @escaping () -> Void,
    onRelease: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 10) {
      Label("按需资源 · 默认安装", systemImage: "shippingbox")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)

      Spacer(minLength: 8)

      if availability == .available {
        Button("卸载", role: .destructive, action: onRelease)
          .disabled(releasingIDs.contains(id) || downloadingIDs.contains(id))
          .accessibilityIdentifier("knowledgePacks.release.\(id)")
      } else {
        Button(action: onDownload) {
          if downloadingIDs.contains(id) {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(availability == .notDownloaded ? "下载" : "重试")
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(CultureTheme.cinnabar)
        .disabled(downloadingIDs.contains(id) || releasingIDs.contains(id))
        .accessibilityIdentifier("knowledgePacks.download.\(id)")
      }

      if releasingIDs.contains(id) {
        ProgressView()
          .controlSize(.small)
      }
    }
  }

  private func packActions(
    id: String,
    availability: ImagePackResource.Availability,
    onDownload: @escaping () -> Void,
    onRelease: @escaping () -> Void
  ) -> some View {
    let mapped: KnowledgePackResource.Availability =
      switch availability {
      case .available: .available
      case .notDownloaded: .notDownloaded
      case .unavailable: .unavailable
      }
    return packActions(
      id: id,
      availability: mapped,
      onDownload: onDownload,
      onRelease: onRelease
    )
  }

  private func metric(value: Int, label: LocalizedStringKey) -> some View {
    VStack(spacing: 2) {
      Text(value, format: .number)
        .font(CultureTypography.title(.title3))
        .foregroundStyle(CultureTheme.inkPrimary)
      Text(label)
        .font(.caption2)
        .foregroundStyle(CultureTheme.inkSecondary)
    }
    .frame(maxWidth: .infinity)
  }

  private func statusBadge(_ availability: KnowledgePackResource.Availability) -> some View {
    Text(availability.title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(availability.foregroundStyle)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(availability.backgroundStyle, in: Capsule())
  }

  private func statusBadge(_ availability: ImagePackResource.Availability) -> some View {
    Text(availability.title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(availability.foregroundStyle)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(availability.backgroundStyle, in: Capsule())
  }

  @MainActor
  private func refresh() async {
    isLoading = true
    errorMessage = nil
    async let knowledge = KnowledgePackLoader.shared.resourceStatuses()
    async let images = ImagePackLoader.shared.resourceStatus()
    resources = await knowledge
    imagePack = await images
    isLoading = false
  }

  @MainActor
  private func download(_ resource: KnowledgePackResource) async {
    guard downloadingIDs.insert(resource.id).inserted else { return }
    errorMessage = nil
    defer { downloadingIDs.remove(resource.id) }

    do {
      try await KnowledgePackLoader.shared.downloadOnDemandPack(resource.directory)
      resources = await KnowledgePackLoader.shared.resourceStatuses()
    } catch {
      errorMessage = error.localizedDescription
      resources = await KnowledgePackLoader.shared.resourceStatuses()
    }
  }

  @MainActor
  private func downloadImagePack(_ resource: ImagePackResource) async {
    guard downloadingIDs.insert(resource.id).inserted else { return }
    errorMessage = nil
    defer { downloadingIDs.remove(resource.id) }

    do {
      try await ImagePackLoader.shared.downloadOnDemandPack()
      imagePack = await ImagePackLoader.shared.resourceStatus()
    } catch {
      errorMessage = error.localizedDescription
      imagePack = await ImagePackLoader.shared.resourceStatus()
    }
  }

  @MainActor
  private func release(_ target: ReleaseTarget) async {
    let id = target.id
    guard releasingIDs.insert(id).inserted else { return }
    errorMessage = nil
    defer { releasingIDs.remove(id) }

    switch target {
    case .knowledge(let resource):
      await KnowledgePackLoader.shared.releaseOnDemandPack(resource.directory)
      resources = await KnowledgePackLoader.shared.resourceStatuses()
      if resources.contains(where: { $0.id == resource.id && $0.availability == .available }) {
        errorMessage = String(
          localized: "知识包仍可访问：当前构建把资源嵌在 App 内，卸载只能结束访问声明，无法删盘。"
        )
      }
    case .images:
      await ImagePackLoader.shared.releaseOnDemandPack()
      imagePack = await ImagePackLoader.shared.resourceStatus()
      if imagePack?.availability == .available {
        errorMessage = String(
          localized: "图片包仍可访问：当前构建把资源嵌在 App 内，卸载只能结束访问声明，无法删盘。"
        )
      }
    }
  }
}

private enum ReleaseTarget: Identifiable {
  case knowledge(KnowledgePackResource)
  case images(ImagePackResource)

  var id: String {
    switch self {
    case .knowledge(let resource): resource.id
    case .images(let resource): resource.id
    }
  }
}

extension KnowledgePackDirectory {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .unified: "文化知识库"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .unified: "books.vertical"
    }
  }
}

extension KnowledgePackResource.Availability {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .available: "可用"
    case .notDownloaded: "未下载"
    case .unavailable: "异常"
    }
  }

  fileprivate var foregroundStyle: Color {
    switch self {
    case .available: .green
    case .notDownloaded: CultureTheme.antiqueGold
    case .unavailable: .red
    }
  }

  fileprivate var backgroundStyle: Color {
    foregroundStyle.opacity(0.12)
  }
}

extension ImagePackResource.Availability {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .available: "可用"
    case .notDownloaded: "未下载"
    case .unavailable: "异常"
    }
  }

  fileprivate var foregroundStyle: Color {
    switch self {
    case .available: .green
    case .notDownloaded: CultureTheme.antiqueGold
    case .unavailable: .red
    }
  }

  fileprivate var backgroundStyle: Color {
    foregroundStyle.opacity(0.12)
  }
}

#Preview {
  NavigationStack {
    KnowledgePackManagerView()
  }
}
