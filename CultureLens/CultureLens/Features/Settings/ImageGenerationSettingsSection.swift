import SwiftUI

/// Settings toggle for optional Seedream cover generation (default off).
struct ImageGenerationSettingsSection: View {
  @Environment(ImageGenerationPreferenceStore.self) private var imageStore

  var body: some View {
    @Bindable var imageStore = imageStore

    VStack(alignment: .leading, spacing: 14) {
      MagazineSectionHeader(
        eyebrow: "IMAGE",
        "图片生成",
        subtitle: "分享文化回顾时，若知识介绍没有配图，可选用火山方舟 Seedream 生成封面。默认关闭。"
      )

      Toggle(isOn: $imageStore.isEnabled) {
        VStack(alignment: .leading, spacing: 4) {
          Text("启用 Seedream 封面生成")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(CultureTheme.inkPrimary)
          Text("仅在分享且缺少介绍主图时调用；会消耗方舟额度。")
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .tint(CultureTheme.cinnabar)
      .accessibilityIdentifier("settings.imageGenerationToggle")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
