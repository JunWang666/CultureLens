import SwiftUI

struct CacheSettingsSection: View {
  @State private var isClearing = false
  @State private var showsConfirmation = false
  @State private var statusMessage: LocalizedStringKey?
  @State private var usageBytes: Int64?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MagazineSectionHeader(
        eyebrow: "CACHE",
        "网络缓存",
        subtitle: "在线图片、朗读音频和即时译文会缓存在本地；AI 文化讲解会作为内容持久保存。"
      )

      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          if let statusMessage {
            Label(statusMessage, systemImage: "checkmark.circle")
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          } else {
            Text("当前占用")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(CultureTheme.inkPrimary)
          }

          Text(usageLabel)
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
            .monospacedDigit()
        }

        Spacer(minLength: 8)

        Button("清理缓存", role: .destructive) {
          showsConfirmation = true
        }
        .disabled(isClearing || (usageBytes ?? 0) == 0)
        .accessibilityIdentifier("settings.clearNetworkCache")

        if isClearing {
          ProgressView()
            .controlSize(.small)
        }
      }
      .padding(.vertical, CultureTheme.rowPadding)
      .accessibilityElement(children: .combine)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task { await refreshUsage() }
    .alert("清理网络缓存？", isPresented: $showsConfirmation) {
      Button("取消", role: .cancel) {}
      Button("清理", role: .destructive) {
        clearCaches()
      }
    } message: {
      Text("在线图片、朗读音频和即时译文缓存会被删除；AI 讲解、扫描历史、问答记录、文化图谱和资源包（含图片 ODR）不会受影响。")
    }
  }

  private var usageLabel: String {
    guard let usageBytes else { return "计算中…" }
    return AppCacheManager.formattedUsage(usageBytes)
  }

  private func refreshUsage() async {
    usageBytes = await AppCacheManager.usageBytes()
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
      await refreshUsage()
    }
  }
}
