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

          CacheSettingsSection()

          NavigationLink {
            KnowledgePackManagerView()
          } label: {
            HStack(spacing: 16) {
              Image(systemName: "shippingbox")
                .font(.title3)
                .foregroundStyle(CultureTheme.antiqueGold)
                .frame(width: 36)

              VStack(alignment: .leading, spacing: 4) {
                Text("资源包管理")
                  .font(.headline)
                  .foregroundStyle(CultureTheme.inkPrimary)
                Text("查看知识包状态、版本与内容，并重新下载缺失资源。")
                  .font(.caption)
                  .foregroundStyle(CultureTheme.inkSecondary)
                  .fixedSize(horizontal: false, vertical: true)
              }

              Spacer(minLength: 8)

              Image(systemName: "chevron.right")
                .font(.body.weight(.semibold))
                .foregroundStyle(CultureTheme.inkSecondary)
                .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              CultureTheme.surface.opacity(0.72),
              in: RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("settings.openKnowledgePacks")
        }
        .padding(.horizontal, CultureTheme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 40)
      }
    }
    .cultureNavigationTitle("设置", showsBackButton: showsBackButton)
  }
}

#Preview {
  NavigationStack {
    SettingsView(showsBackButton: false)
  }
  .environment(AppLanguageStore())
}
