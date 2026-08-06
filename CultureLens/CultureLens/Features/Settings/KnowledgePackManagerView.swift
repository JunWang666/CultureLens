import SwiftUI

/// Lists the independently tagged knowledge ODR packs and the image pack, and
/// lets users retry a missing initial-install resource without changing pack
/// merge semantics.
struct KnowledgePackManagerView: View {
  @State private var resources: [KnowledgePackResource] = []
  @State private var imagePack: ImagePackResource?
  @State private var isLoading = true
  @State private var downloadingIDs = Set<String>()
  @State private var errorMessage: String?

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
            VStack(alignment: .leading, spacing: 0) {
          ForEach(resources) { resource in
            if resource.id == resources.first?.id {
              EditorialRule()
            }
            resourceCard(resource)
          }
          if let imagePack {
            if resources.isEmpty {
              EditorialRule()
            }
            imagePackCard(imagePack)
          }
            }
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
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
  }

  private var introduction: some View {
    MagazinePageHeader(
      eyebrow: "PACKS",
      title: "知识与图片资源包",
      message: "知识包与图片包首次安装时默认随 App 交付；若系统清理了按需资源，可在这里单独重新下载。图片包会拦截对应的远程图片请求，优先读本地文件。"
    )
  }

  private func resourceCard(_ resource: KnowledgePackResource) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text(resource.directory.title)
            .font(.magazineDisplay(.headline))
            .foregroundStyle(CultureTheme.inkPrimary)
          if let version = resource.version {
            Text(version)
              .font(.caption.monospaced())
              .foregroundStyle(CultureTheme.inkSecondary)
          }
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
      } else {
        Text(resource.availability == .notDownloaded ? "此资源包当前不在设备上。" : "资源包文件无法读取，请重试。")
          .font(.footnote)
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      EditorialRule()

      HStack(spacing: 10) {
        Label("按需资源 · 默认安装", systemImage: "shippingbox")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)

        Spacer(minLength: 8)

        if resource.availability != .available {
          Button {
            Task { await download(resource) }
          } label: {
            if downloadingIDs.contains(resource.id) {
              ProgressView()
                .controlSize(.small)
            } else {
              Text(resource.availability == .notDownloaded ? "下载" : "重试")
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.cinnabar)
          .disabled(downloadingIDs.contains(resource.id))
          .accessibilityIdentifier("knowledgePacks.download.\(resource.id)")
        }
      }
    }
    .padding(.vertical, CultureTheme.rowPadding)
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private func imagePackCard(_ resource: ImagePackResource) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 4) {
          Text("知识配图")
            .font(.magazineDisplay(.headline))
            .foregroundStyle(CultureTheme.inkPrimary)
          Text(ImagePackLoader.odrTag)
            .font(.caption.monospaced())
            .foregroundStyle(CultureTheme.inkSecondary)
        }

        Spacer(minLength: 8)
        statusBadge(resource.availability)
      }

      if resource.availability == .available {
        HStack(spacing: 0) {
          metric(value: resource.imageCount, label: "配图")
        }
      } else {
        Text(resource.availability == .notDownloaded ? "此图片包当前不在设备上。" : "图片包文件无法读取，请重试。")
          .font(.footnote)
          .foregroundStyle(CultureTheme.inkSecondary)
      }

      EditorialRule()

      HStack(spacing: 10) {
        Label("按需资源 · 默认安装", systemImage: "shippingbox")
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)

        Spacer(minLength: 8)

        if resource.availability != .available {
          Button {
            Task { await downloadImagePack(resource) }
          } label: {
            if downloadingIDs.contains(resource.id) {
              ProgressView()
                .controlSize(.small)
            } else {
              Text(resource.availability == .notDownloaded ? "下载" : "重试")
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(CultureTheme.cinnabar)
          .disabled(downloadingIDs.contains(resource.id))
          .accessibilityIdentifier("knowledgePacks.download.images")
        }
      }
    }
    .padding(.vertical, CultureTheme.rowPadding)
    .overlay(alignment: .bottom) { EditorialRule() }
  }

  private func metric(value: Int, label: LocalizedStringKey) -> some View {
    VStack(spacing: 2) {
      Text(value, format: .number)
        .font(.magazineDisplay(.title3))
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
}

extension KnowledgePackDirectory {
  fileprivate var title: LocalizedStringKey {
    switch self {
    case .westLake: "杭州西湖"
    case .chineseHistory: "中国历史"
    case .liangzhu: "良渚文化"
    case .zhejiangMuseum: "浙江省博物馆"
    }
  }

  fileprivate var systemImage: String {
    switch self {
    case .westLake: "water.waves"
    case .chineseHistory: "scroll"
    case .liangzhu: "seal"
    case .zhejiangMuseum: "building.columns"
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
