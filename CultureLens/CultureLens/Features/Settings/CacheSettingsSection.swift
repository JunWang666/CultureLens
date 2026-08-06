import SwiftUI

struct CacheSettingsSection: View {
  @State private var isClearing = false
  @State private var showsConfirmation = false
  @State private var statusMessage: LocalizedStringKey?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MagazineSectionHeader(eyebrow: "CACHE", "网络缓存")
        .padding(.bottom, 8)

      Text("在线图片和即时译文会缓存在本地；AI 文化讲解会作为内容持久保存。")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, CultureTheme.rowPadding)

      EditorialRule()

      HStack {
        if let statusMessage {
          Label(statusMessage, systemImage: "checkmark.circle")
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
        }

        Spacer(minLength: 12)

        Button("清理缓存", role: .destructive) {
          showsConfirmation = true
        }
        .disabled(isClearing)
        .accessibilityIdentifier("settings.clearNetworkCache")

        if isClearing {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding(.vertical, CultureTheme.rowPadding)

      EditorialRule()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .alert("清理网络缓存？", isPresented: $showsConfirmation) {
      Button("取消", role: .cancel) {}
      Button("清理", role: .destructive) {
        clearCaches()
      }
    } message: {
      Text("在线图片和即时译文缓存会被删除；AI 讲解、扫描历史、问答记录、文化图谱和资源包（含图片 ODR）不会受影响。")
    }
  }

  private func clearCaches() {
    guard !isClearing else { return }
    isClearing = true
    statusMessage = nil
    Task {
      defer { isClearing = false }
      do {
        try await AppCacheManager.clearAll()
        statusMessage = "缓存已清理"
      } catch {
        statusMessage = "部分缓存未能清理，请稍后重试"
      }
    }
  }
}
