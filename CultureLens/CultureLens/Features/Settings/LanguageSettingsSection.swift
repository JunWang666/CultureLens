import SwiftUI

/// Language preference controls for the Profile tab.
struct LanguageSettingsSection: View {
  @Environment(AppLanguageStore.self) private var languageStore

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      MagazineSectionHeader(eyebrow: "LANGUAGE", "语言")

      Text("界面文案随语言切换；识别、讲解与问答由模型直接用目标语言回答。知识库译文尚未打包时，会通过聊天模型即时翻译。")
        .font(.footnote)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)

      Picker("语言", selection: Bindable(languageStore).preference) {
        ForEach(AppLanguagePreference.allCases) { preference in
          preferenceLabel(preference).tag(preference)
        }
      }
      .pickerStyle(.menu)
      .accessibilityIdentifier("languagePreferencePicker")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// Only "跟随系统" localizes; language names stay in their native form.
  private func preferenceLabel(_ preference: AppLanguagePreference) -> Text {
    switch preference {
    case .system:
      Text("跟随系统")
    case .zhHans:
      Text(verbatim: AppLanguage.zhHans.nativeDisplayName)
    case .english:
      Text(verbatim: AppLanguage.english.nativeDisplayName)
    case .japanese:
      Text(verbatim: AppLanguage.japanese.nativeDisplayName)
    case .russian:
      Text(verbatim: AppLanguage.russian.nativeDisplayName)
    }
  }
}
