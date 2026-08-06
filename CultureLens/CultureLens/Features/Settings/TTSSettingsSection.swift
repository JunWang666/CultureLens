import AVFoundation
import SwiftUI

/// TTS engine + voice controls for the Settings tab.
struct TTSSettingsSection: View {
  @Environment(TTSPreferenceStore.self) private var ttsStore
  @Environment(AppLanguageStore.self) private var languageStore

  var body: some View {
    @Bindable var ttsStore = ttsStore

    VStack(alignment: .leading, spacing: 14) {
      MagazineSectionHeader(
        eyebrow: "SPEECH",
        "朗读",
        subtitle: "讲解、介绍与问答等长文本可朗读。火山引擎失败时会自动回退到系统朗读。"
      )

      VStack(alignment: .leading, spacing: 8) {
        Text("引擎")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)

        Picker("引擎", selection: $ttsStore.engine) {
          ForEach(TTSEnginePreference.allCases) { preference in
            Text(preference.title).tag(preference)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("tts.enginePicker")

        Text(ttsStore.engine.detail)
          .font(.caption)
          .foregroundStyle(CultureTheme.inkSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      switch ttsStore.engine {
      case .volcengine:
        playbackPriorityPicker(ttsStore: ttsStore)
        volcengineVoicePicker(ttsStore: ttsStore)
      case .system:
        systemVoicePicker(ttsStore: ttsStore)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func playbackPriorityPicker(ttsStore: TTSPreferenceStore) -> some View {
    @Bindable var ttsStore = ttsStore

    VStack(alignment: .leading, spacing: 8) {
      Text("播放策略")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)

      Picker("播放策略", selection: $ttsStore.playbackPriority) {
        ForEach(TTSPlaybackPriority.allCases) { priority in
          Text(priority.title).tag(priority)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("tts.playbackPriorityPicker")

      Text(ttsStore.playbackPriority.detail)
        .font(.caption)
        .foregroundStyle(CultureTheme.inkSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder
  private func volcengineVoicePicker(ttsStore: TTSPreferenceStore) -> some View {
    @Bindable var ttsStore = ttsStore

    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 12) {
        Text("火山引擎音色")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(CultureTheme.inkPrimary)

        Spacer(minLength: 8)

        Picker("音色", selection: $ttsStore.volcengineVoiceID) {
          ForEach(VolcengineVoiceOption.catalog) { voice in
            Text(verbatim: voice.displayName(for: languageStore.language))
              .tag(voice.speakerID)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .tint(CultureTheme.cinnabar)
        .accessibilityIdentifier("tts.volcengineVoicePicker")
      }

      Text(verbatim: ttsStore.selectedVolcengineVoice.speakerID)
        .font(.caption2.monospaced())
        .foregroundStyle(CultureTheme.inkSecondary)
        .textSelection(.enabled)
    }
  }

  @ViewBuilder
  private func systemVoicePicker(ttsStore: TTSPreferenceStore) -> some View {
    @Bindable var ttsStore = ttsStore
    let voices = TTSPreferenceStore.systemVoices(for: languageStore.language)

    HStack(alignment: .center, spacing: 12) {
      Text("系统音色")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)

      Spacer(minLength: 8)

      Picker("音色", selection: $ttsStore.systemVoiceIdentifier) {
        Text("系统默认").tag("")
        ForEach(voices, id: \.identifier) { voice in
          Text(verbatim: "\(voice.name)（\(voice.language)）")
            .tag(voice.identifier)
        }
      }
      .pickerStyle(.menu)
      .labelsHidden()
      .tint(CultureTheme.cinnabar)
      .accessibilityIdentifier("tts.systemVoicePicker")
    }
  }
}
