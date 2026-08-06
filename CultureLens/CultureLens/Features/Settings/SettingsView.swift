import SwiftUI

/// Standalone settings tab (language preference and related controls).
struct SettingsView: View {
  var showsBackButton: Bool = true

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: CultureTheme.sectionSpacing) {
          MagazinePageHeader(
            eyebrow: "SETTINGS",
            title: "设置",
            message: "语言、缓存与资源包工具。"
          )

          LanguageSettingsSection()

          CacheSettingsSection()

          VStack(alignment: .leading, spacing: 0) {
            MagazineSectionHeader(eyebrow: "PACKS", "资源包")
              .padding(.bottom, 4)

            NavigationLink {
              KnowledgePackManagerView()
            } label: {
              MagazineDestinationRow(
                title: "资源包管理",
                message: "查看知识包状态、版本与内容，并重新下载缺失资源。",
                systemImage: "shippingbox"
              )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.openKnowledgePacks")

            EditorialRule()

            PackEditorSettingsSection()
          }

          MagazineFooterOrnament()
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 20)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("设置", showsBackButton: showsBackButton)
  }
}

/// Entry row into the on-device knowledge-pack editor / exporter.
private struct PackEditorSettingsSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("制作或编辑知识包 sidecar，校验后导出 zip，便于更新 Resources/KnowledgePack*。")
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 4)

      NavigationLink(value: AppRoute.packEditor) {
        MagazineDestinationRow(
          title: "资源包制作 / 编辑器",
          message: "新建、从内置包复制、导入与导出",
          systemImage: "shippingbox.and.arrow.backward"
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings.openPackEditor")
    }
  }
}

#Preview {
  NavigationStack {
    SettingsView(showsBackButton: false)
  }
  .environment(AppLanguageStore())
}
