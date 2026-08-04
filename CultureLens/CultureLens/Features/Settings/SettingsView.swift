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
