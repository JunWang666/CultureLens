import AVFoundation
import Foundation
import SwiftUI

/// Which speech engine to prefer for朗读.
nonisolated enum TTSEnginePreference: String, CaseIterable, Identifiable, Codable, Sendable {
  case volcengine
  case system

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .volcengine: "火山引擎"
    case .system: "系统"
    }
  }

  var detail: LocalizedStringKey {
    switch self {
    case .volcengine: "优先火山引擎，失败时回退系统朗读"
    case .system: "仅使用 iOS 自带朗读"
    }
  }
}

/// Latency vs smoothness trade-off for Volcengine streaming TTS.
nonisolated enum TTSPlaybackPriority: String, CaseIterable, Identifiable, Codable, Sendable {
  case speed
  case smooth

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .speed: "速度优先"
    case .smooth: "流畅优先"
    }
  }

  var detail: LocalizedStringKey {
    switch self {
    case .speed: "收到首段音频即开始播，弱网时可能卡顿"
    case .smooth: "整段合成完成后再播，更稳但首包更慢"
    }
  }

  /// Bytes of s16le mono PCM to buffer before starting playback (speed mode).
  var startupBufferBytes: Int {
    switch self {
    case .speed:
      // ~0.35s at 24 kHz s16le mono — start soon without waiting for the whole reply.
      24_000 * 2 * 35 / 100
    case .smooth:
      // Wait for the full stream; threshold unused.
      Int.max
    }
  }
}

/// Curated Volcengine Doubao TTS 2.0 (`seed-tts-2.0` / uranus) voices.
nonisolated struct VolcengineVoiceOption: Identifiable, Hashable, Sendable {
  let speakerID: String
  let nameZh: String
  let nameEn: String

  var id: String { speakerID }

  func displayName(for language: AppLanguage) -> String {
    switch language {
    case .english: nameEn
    case .zhHans: nameZh
    }
  }

  static let catalog: [VolcengineVoiceOption] = [
    .init(
      speakerID: "zh_male_qingshuangnanda_uranus_bigtts",
      nameZh: "清爽男大",
      nameEn: "Qingshuang Nanda"
    ),
    .init(
      speakerID: "zh_female_xiaohe_uranus_bigtts",
      nameZh: "小何",
      nameEn: "Xiaohe"
    ),
    .init(
      speakerID: "zh_female_shuangkuaisisi_uranus_bigtts",
      nameZh: "爽快思思",
      nameEn: "Shuangkuai Sisi"
    ),
    .init(
      speakerID: "zh_female_vv_uranus_bigtts",
      nameZh: "Vivi",
      nameEn: "Vivi"
    ),
    .init(
      speakerID: "zh_female_gaolengyujie_uranus_bigtts",
      nameZh: "高冷御姐",
      nameEn: "Gaoleng Yujie"
    ),
    .init(
      speakerID: "zh_male_m191_uranus_bigtts",
      nameZh: "云舟",
      nameEn: "Yunzhou"
    ),
    .init(
      speakerID: "zh_male_taocheng_uranus_bigtts",
      nameZh: "小天",
      nameEn: "Xiaotian"
    ),
    .init(
      speakerID: "en_female_dacey_uranus_bigtts",
      nameZh: "Dacey（英）",
      nameEn: "Dacey (EN)"
    ),
    .init(
      speakerID: "en_male_tim_uranus_bigtts",
      nameZh: "Tim（英）",
      nameEn: "Tim (EN)"
    ),
  ]

  static let defaultSpeakerID = "zh_male_qingshuangnanda_uranus_bigtts"

  static func option(for speakerID: String) -> VolcengineVoiceOption? {
    catalog.first { $0.speakerID == speakerID }
  }
}

/// Persisted TTS engine + voice preferences.
@Observable
@MainActor
final class TTSPreferenceStore {
  nonisolated static let engineKey = "culturelens.tts.engine"
  nonisolated static let volcengineVoiceKey = "culturelens.tts.volcengineVoice"
  nonisolated static let systemVoiceKey = "culturelens.tts.systemVoice"
  nonisolated static let playbackPriorityKey = "culturelens.tts.playbackPriority"

  var engine: TTSEnginePreference {
    didSet {
      UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey)
      CultureTTSController.shared.stop()
    }
  }

  /// Volcengine speaker id (`*_uranus_bigtts`).
  var volcengineVoiceID: String {
    didSet {
      UserDefaults.standard.set(volcengineVoiceID, forKey: Self.volcengineVoiceKey)
      CultureTTSController.shared.stop()
    }
  }

  /// `AVSpeechSynthesisVoice.identifier`, or empty for language default.
  var systemVoiceIdentifier: String {
    didSet {
      UserDefaults.standard.set(systemVoiceIdentifier, forKey: Self.systemVoiceKey)
      CultureTTSController.shared.stop()
    }
  }

  /// Speed (low latency stream) vs smooth (fully buffered playback).
  var playbackPriority: TTSPlaybackPriority {
    didSet {
      UserDefaults.standard.set(playbackPriority.rawValue, forKey: Self.playbackPriorityKey)
      CultureTTSController.shared.stop()
    }
  }

  init(
    engine: TTSEnginePreference = TTSPreferenceStore.loadEngine(),
    volcengineVoiceID: String = TTSPreferenceStore.loadVolcengineVoiceID(),
    systemVoiceIdentifier: String = TTSPreferenceStore.loadSystemVoiceIdentifier(),
    playbackPriority: TTSPlaybackPriority = TTSPreferenceStore.loadPlaybackPriority()
  ) {
    self.engine = engine
    self.volcengineVoiceID = volcengineVoiceID
    self.systemVoiceIdentifier = systemVoiceIdentifier
    self.playbackPriority = playbackPriority
  }

  var selectedVolcengineVoice: VolcengineVoiceOption {
    VolcengineVoiceOption.option(for: volcengineVoiceID)
      ?? VolcengineVoiceOption.option(for: VolcengineVoiceOption.defaultSpeakerID)!
  }

  nonisolated static func loadEngine() -> TTSEnginePreference {
    guard let raw = UserDefaults.standard.string(forKey: engineKey),
      let value = TTSEnginePreference(rawValue: raw)
    else {
      return .volcengine
    }
    return value
  }

  nonisolated static func loadVolcengineVoiceID() -> String {
    let raw = UserDefaults.standard.string(forKey: volcengineVoiceKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !raw.isEmpty, VolcengineVoiceOption.option(for: raw) != nil {
      return raw
    }
    return VolcengineVoiceOption.defaultSpeakerID
  }

  nonisolated static func loadSystemVoiceIdentifier() -> String {
    UserDefaults.standard.string(forKey: systemVoiceKey) ?? ""
  }

  nonisolated static func loadPlaybackPriority() -> TTSPlaybackPriority {
    guard let raw = UserDefaults.standard.string(forKey: playbackPriorityKey),
      let value = TTSPlaybackPriority(rawValue: raw)
    else {
      // Prefer smooth by default — streaming is too sensitive to weak networks.
      return .smooth
    }
    return value
  }

  nonisolated static func currentEngine() -> TTSEnginePreference {
    loadEngine()
  }

  nonisolated static func currentVolcengineVoiceID() -> String {
    loadVolcengineVoiceID()
  }

  nonisolated static func currentSystemVoiceIdentifier() -> String {
    loadSystemVoiceIdentifier()
  }

  nonisolated static func currentPlaybackPriority() -> TTSPlaybackPriority {
    loadPlaybackPriority()
  }

  /// System voices matching the app content language (plus a “default” option).
  static func systemVoices(for language: AppLanguage) -> [AVSpeechSynthesisVoice] {
    let code: String
    switch language {
    case .zhHans: code = "zh-CN"
    case .english: code = "en-US"
    }
    return AVSpeechSynthesisVoice.speechVoices()
      .filter { $0.language.hasPrefix(code.prefix(2)) }
      .sorted { lhs, rhs in
        if lhs.language == code && rhs.language != code { return true }
        if rhs.language == code && lhs.language != code { return false }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
  }
}

extension VolcengineTTSConfig {
  /// Credentials from `.default`, speakers from the user’s voice preference.
  static func resolved(
    voiceID: String = TTSPreferenceStore.loadVolcengineVoiceID()
  ) -> VolcengineTTSConfig {
    let base = VolcengineTTSConfig.default
    let speaker =
      VolcengineVoiceOption.option(for: voiceID)?.speakerID
      ?? VolcengineVoiceOption.defaultSpeakerID
    return VolcengineTTSConfig(
      endpoint: base.endpoint,
      apiKey: base.apiKey,
      appId: base.appId,
      accessKey: base.accessKey,
      resourceId: base.resourceId,
      chineseSpeaker: speaker,
      englishSpeaker: speaker,
      sampleRate: base.sampleRate,
      timeout: base.timeout
    )
  }
}
