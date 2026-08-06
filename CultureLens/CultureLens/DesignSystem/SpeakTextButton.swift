import SwiftUI

/// Icon-only speak / stop control bound to `CultureTTSController.shared`.
struct SpeakTextButton: View {
  let utteranceID: String
  let text: String
  var accessibilityLabelKey: LocalizedStringKey = "朗读"

  @Environment(AppLanguageStore.self) private var languageStore

  private var controller: CultureTTSController { .shared }

  private var isLoading: Bool { controller.isLoading(utteranceID: utteranceID) }
  private var isPlaying: Bool { controller.isPlaying(utteranceID: utteranceID) }
  private var isActive: Bool { controller.isActive(utteranceID: utteranceID) }

  private var speakable: String {
    SpeechTextNormalizer.plainSpeechText(from: text)
  }

  var body: some View {
    Group {
      if isLoading {
        ProgressView()
          .controlSize(.small)
          .accessibilityLabel("正在准备朗读")
      } else {
        Button(isPlaying ? "停止朗读" : accessibilityLabelKey, systemImage: systemImage) {
          controller.toggle(
            utteranceID: utteranceID,
            text: speakable,
            language: languageStore.language
          )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(CultureTheme.cinnabar)
        .disabled(speakable.isEmpty)
        .accessibilityHint(isPlaying ? "停止当前朗读" : "朗读当前内容")
        .accessibilityIdentifier("tts.speak.\(utteranceID)")
      }
    }
    .opacity(speakable.isEmpty ? 0.35 : 1)
  }

  private var systemImage: String {
    isPlaying ? "stop.fill" : "speaker.wave.2"
  }
}
