import SwiftUI

/// Standalone settings tab (language preference and related controls).
struct SettingsView: View {
  var showsBackButton: Bool = true

  var body: some View {
    ZStack {
      CulturePageBackground()

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 16) {
          LanguageSettingsSection()
          PackEditorSettingsSection()
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("设置", showsBackButton: showsBackButton)
  }
}

/// Entry card into the on-device knowledge-pack editor / exporter.
private struct PackEditorSettingsSection: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("工具")
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)

      Text("制作或编辑知识包 sidecar，校验后导出 zip，便于更新 Resources/KnowledgePack*。")
        .font(.footnote)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      NavigationLink(value: AppRoute.packEditor) {
        HStack(spacing: 12) {
          Image(systemName: "shippingbox.and.arrow.backward")
            .foregroundStyle(CultureTheme.antiqueGold)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("资源包制作 / 编辑器")
              .font(.body.weight(.semibold))
              .foregroundStyle(CultureTheme.inkPrimary)
            Text("新建、从内置包复制、导入与导出")
              .font(.caption)
              .foregroundStyle(CultureTheme.inkSecondary)
          }
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.body.weight(.semibold))
            .foregroundStyle(CultureTheme.inkSecondary)
        }
        .padding(14)
        .background(
          CultureTheme.surface.opacity(0.9),
          in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings.openPackEditor")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CultureTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
  }
}

#Preview {
  NavigationStack {
    SettingsView(showsBackButton: false)
  }
  .environment(AppLanguageStore())
}
