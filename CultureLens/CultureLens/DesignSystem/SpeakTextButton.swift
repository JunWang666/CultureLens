import SwiftUI

/// Speak control with pause / resume / stop — pause keeps position; stop ends the session.
struct SpeakTextButton: View {
  let utteranceID: String
  let text: String
  var accessibilityLabelKey: LocalizedStringKey = "朗读"

  @Environment(AppLanguageStore.self) private var languageStore

  private var controller: CultureTTSController { .shared }

  private var isLoading: Bool { controller.isLoading(utteranceID: utteranceID) }
  private var isPlaying: Bool { controller.isPlaying(utteranceID: utteranceID) }
  private var isPaused: Bool { controller.isPaused(utteranceID: utteranceID) }
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
      } else if isActive {
        HStack(spacing: 12) {
          Button(isPaused ? "继续朗读" : "暂停朗读", systemImage: isPaused ? "play.fill" : "pause.fill") {
            controller.toggle(
              utteranceID: utteranceID,
              text: speakable,
              language: languageStore.language
            )
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.plain)
          .foregroundStyle(CultureTheme.cinnabar)
          .accessibilityHint(isPaused ? "从暂停处继续" : "暂停当前朗读")
          .accessibilityIdentifier("tts.pause.\(utteranceID)")

          Button("停止朗读", systemImage: "stop.fill") {
            controller.stop()
          }
          .labelStyle(.iconOnly)
          .buttonStyle(.plain)
          .foregroundStyle(CultureTheme.inkSecondary)
          .accessibilityHint("结束朗读，下次从头播放")
          .accessibilityIdentifier("tts.stop.\(utteranceID)")
        }
      } else {
        Button(accessibilityLabelKey, systemImage: "speaker.wave.2") {
          controller.speak(
            utteranceID: utteranceID,
            text: speakable,
            language: languageStore.language
          )
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(CultureTheme.cinnabar)
        .disabled(speakable.isEmpty)
        .accessibilityHint("朗读当前内容")
        .accessibilityIdentifier("tts.speak.\(utteranceID)")
      }
    }
    .opacity(speakable.isEmpty ? 0.35 : 1)
  }
}
