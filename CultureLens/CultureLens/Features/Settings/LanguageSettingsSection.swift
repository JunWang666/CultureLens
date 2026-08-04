import SwiftUI

/// Language preference controls for the Profile tab.
struct LanguageSettingsSection: View {
  @Environment(AppLanguageStore.self) private var languageStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("语言")
        .font(.headline)
        .foregroundStyle(CultureTheme.inkPrimary)

      Text("界面文案随语言切换；识别、讲解与问答由模型直接用目标语言回答。知识库译文尚未打包时，会通过聊天模型即时翻译。")
        .font(.footnote)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Picker("语言", selection: Bindable(languageStore).preference) {
        ForEach(AppLanguagePreference.allCases) { preference in
          Text(preference.title).tag(preference)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("languagePreferencePicker")
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(CultureTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
  }
}
