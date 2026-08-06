import AVFoundation
import Foundation
import Observation

/// Shared speak/stop controller: Volcengine MP3 first, then iOS `AVSpeechSynthesizer`.
@Observable
@MainActor
final class CultureTTSController: NSObject {
  static let shared = CultureTTSController()

  enum Engine: String, Sendable {
    case volcengine
    case system
  }

  enum PlaybackState: Equatable {
    case idle
    case loading(utteranceID: String)
    case playing(utteranceID: String, engine: Engine)
  }

  private(set) var state: PlaybackState = .idle

  private let client: VolcengineTTSClient
  private let synthesizer = AVSpeechSynthesizer()
  private var audioPlayer: AVAudioPlayer?
  private var speakTask: Task<Void, Never>?
  private var activeUtteranceID: String?

  init(client: VolcengineTTSClient = VolcengineTTSClient()) {
    self.client = client
    super.init()
    synthesizer.delegate = self
  }

  func isActive(utteranceID: String) -> Bool {
    switch state {
    case .loading(utteranceID), .playing(utteranceID, _):
      true
    default:
      false
    }
  }

  func isLoading(utteranceID: String) -> Bool {
    if case .loading(utteranceID) = state { return true }
    return false
  }

  func isPlaying(utteranceID: String) -> Bool {
    if case .playing(utteranceID, _) = state { return true }
    return false
  }

  func toggle(utteranceID: String, text: String, language: AppLanguage) {
    if isActive(utteranceID: utteranceID) {
      stop()
      return
    }
    speak(utteranceID: utteranceID, text: text, language: language)
  }

  func speak(utteranceID: String, text: String, language: AppLanguage) {
    let normalized = SpeechTextNormalizer.plainSpeechText(from: text)
    guard !normalized.isEmpty else { return }

    stop()
    activeUtteranceID = utteranceID
    state = .loading(utteranceID: utteranceID)

    speakTask = Task { [weak self] in
      guard let self else { return }
      await self.runSpeak(utteranceID: utteranceID, text: normalized, language: language)
    }
  }

  func stop() {
    speakTask?.cancel()
    speakTask = nil
    synthesizer.stopSpeaking(at: .immediate)
    audioPlayer?.stop()
    audioPlayer = nil
    activeUtteranceID = nil
    state = .idle
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func runSpeak(utteranceID: String, text: String, language: AppLanguage) async {
    if client.config.hasCredentials {
      do {
        let mp3 = try await client.synthesize(text: text, language: language)
        guard !Task.isCancelled, activeUtteranceID == utteranceID else { return }
        try playMP3(mp3, utteranceID: utteranceID)
        return
      } catch is CancellationError {
        return
      } catch {
        // Fall through to system TTS.
      }
    }

    guard !Task.isCancelled, activeUtteranceID == utteranceID else { return }
    speakWithSystem(text: text, language: language, utteranceID: utteranceID)
  }

  private func playMP3(_ data: Data, utteranceID: String) throws {
    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try AVAudioSession.sharedInstance().setActive(true)

    let player = try AVAudioPlayer(data: data)
    player.delegate = self
    audioPlayer = player
    guard player.play() else {
      throw VolcengineTTSError.emptyAudio
    }
    state = .playing(utteranceID: utteranceID, engine: .volcengine)
  }

  private func speakWithSystem(text: String, language: AppLanguage, utteranceID: String) {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // Continue; synthesizer may still work with ambient session.
    }

    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = preferredVoice(for: language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    state = .playing(utteranceID: utteranceID, engine: .system)
    synthesizer.speak(utterance)
  }

  private func preferredVoice(for language: AppLanguage) -> AVSpeechSynthesisVoice? {
    let code: String
    switch language {
    case .zhHans: code = "zh-CN"
    case .english: code = "en-US"
    }
    return AVSpeechSynthesisVoice(language: code)
      ?? AVSpeechSynthesisVoice(language: language.localeIdentifier)
  }

  private func finishIfCurrent(_ utteranceID: String?) {
    guard let utteranceID, activeUtteranceID == utteranceID else { return }
    activeUtteranceID = nil
    audioPlayer = nil
    state = .idle
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

extension CultureTTSController: AVAudioPlayerDelegate {
  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      if case .playing(let id, .volcengine) = self.state {
        self.finishIfCurrent(id)
      }
    }
  }
}

extension CultureTTSController: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didFinish utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      if case .playing(let id, .system) = self.state {
        self.finishIfCurrent(id)
      }
    }
  }

  nonisolated func speechSynthesizer(
    _ synthesizer: AVSpeechSynthesizer,
    didCancel utterance: AVSpeechUtterance
  ) {
    Task { @MainActor in
      if case .playing(let id, .system) = self.state {
        self.finishIfCurrent(id)
      }
    }
  }
}
