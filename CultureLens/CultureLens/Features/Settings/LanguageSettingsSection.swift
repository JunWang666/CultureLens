import SwiftUI

/// Language preference controls for the Settings tab.
struct LanguageSettingsSection: View {
  @Environment(AppLanguageStore.self) private var languageStore

  var body: some View {
    @Bindable var languageStore = languageStore

    VStack(alignment: .leading, spacing: 0) {
      MagazineSectionHeader(
        eyebrow: "LANGUAGE",
        "语言",
        subtitle: "界面文案随语言切换；识别、讲解与问答由模型直接用目标语言回答。知识库译文尚未打包时，会通过聊天模型即时翻译。"
      )

      HStack(alignment: .center, spacing: 12) {
        Text("语言")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)

        Spacer(minLength: 8)

        Picker("语言", selection: $languageStore.preference) {
          ForEach(AppLanguagePreference.allCases) { preference in
            preferenceLabel(preference).tag(preference)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(CultureTheme.cinnabar)
        .accessibilityIdentifier("languagePreferencePicker")
      }
      .padding(.vertical, CultureTheme.rowPadding)
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
    }
  }
}
