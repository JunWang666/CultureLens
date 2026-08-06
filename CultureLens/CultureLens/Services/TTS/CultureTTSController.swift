import AVFoundation
import Foundation
import Observation

/// Shared speak controller: stream Volcengine PCM (with disk cache), pause/resume,
/// then fall back to iOS `AVSpeechSynthesizer`.
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
    case paused(utteranceID: String, engine: Engine)
  }

  private(set) var state: PlaybackState = .idle

  private let audioCache: TTSAudioCache
  private let synthesizer = AVSpeechSynthesizer()
  private let streamPlayer = PCMStreamPlayer()
  private var speakTask: Task<Void, Never>?
  private var activeUtteranceID: String?
  private var activeCacheKey: String?
  private var activeNormalizedText: String?
  private var activeLanguage: AppLanguage?
  private var activeConfig: VolcengineTTSConfig?
  /// PCM accumulated for the current Volcengine utterance (live stream or cache).
  private var activePCM = Data()

  init(audioCache: TTSAudioCache = .shared) {
    self.audioCache = audioCache
    super.init()
    synthesizer.delegate = self
    streamPlayer.onFinished = { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        switch self.state {
        case .playing(let id, .volcengine), .paused(let id, .volcengine):
          self.finishIfCurrent(id)
        default:
          break
        }
      }
    }
  }

  func isActive(utteranceID: String) -> Bool {
    switch state {
    case .loading(utteranceID), .playing(utteranceID, _), .paused(utteranceID, _):
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

  func isPaused(utteranceID: String) -> Bool {
    if case .paused(utteranceID, _) = state { return true }
    return false
  }

  /// Primary control: start, pause, or resume the same utterance without restarting.
  func toggle(utteranceID: String, text: String, language: AppLanguage) {
    switch state {
    case .playing(utteranceID, _):
      pause()
    case .paused(utteranceID, _):
      resume()
    case .loading(utteranceID):
      break
    default:
      speak(utteranceID: utteranceID, text: text, language: language)
    }
  }

  func speak(utteranceID: String, text: String, language: AppLanguage) {
    let normalized = SpeechTextNormalizer.plainSpeechText(from: text)
    guard !normalized.isEmpty else { return }

    // Resuming the same utterance should use pause/resume, not restart.
    if isActive(utteranceID: utteranceID),
      activeNormalizedText == normalized,
      activeLanguage == language
    {
      toggle(utteranceID: utteranceID, text: text, language: language)
      return
    }

    stop()
    activeUtteranceID = utteranceID
    activeNormalizedText = normalized
    activeLanguage = language
    let config = VolcengineTTSConfig.resolved()
    activeConfig = config
    activeCacheKey = TTSAudioCache.cacheKey(
      text: normalized,
      language: language,
      config: config
    )
    activePCM = Data()
    state = .loading(utteranceID: utteranceID)

    speakTask = Task { [weak self] in
      guard let self else { return }
      await self.runSpeak(utteranceID: utteranceID, text: normalized, language: language)
    }
  }

  func pause() {
    switch state {
    case .playing(let id, .volcengine):
      streamPlayer.pause()
      state = .paused(utteranceID: id, engine: .volcengine)
    case .playing(let id, .system):
      synthesizer.pauseSpeaking(at: .word)
      state = .paused(utteranceID: id, engine: .system)
    default:
      break
    }
  }

  func resume() {
    switch state {
    case .paused(let id, .volcengine):
      do {
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {}
      streamPlayer.resume()
      state = .playing(utteranceID: id, engine: .volcengine)
    case .paused(let id, .system):
      do {
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {}
      synthesizer.continueSpeaking()
      state = .playing(utteranceID: id, engine: .system)
    default:
      break
    }
  }

  /// Ends playback and resets position. Cached audio is kept for the next start.
  func stop() {
    speakTask?.cancel()
    speakTask = nil
    synthesizer.stopSpeaking(at: .immediate)
    streamPlayer.stop()
    activeUtteranceID = nil
    activeCacheKey = nil
    activeNormalizedText = nil
    activeLanguage = nil
    activeConfig = nil
    activePCM = Data()
    state = .idle
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func runSpeak(utteranceID: String, text: String, language: AppLanguage) async {
    if TTSPreferenceStore.currentEngine() == .volcengine {
      let config = activeConfig ?? VolcengineTTSConfig.resolved()
      if config.hasCredentials {
        do {
          try await playVolcengine(
            utteranceID: utteranceID,
            text: text,
            language: language,
            config: config
          )
          return
        } catch is CancellationError {
          return
        } catch {
          streamPlayer.stop()
          // Fall through to system TTS.
        }
      }
    }

    guard !Task.isCancelled, activeUtteranceID == utteranceID else { return }
    speakWithSystem(text: text, language: language, utteranceID: utteranceID)
  }

  private func playVolcengine(
    utteranceID: String,
    text: String,
    language: AppLanguage,
    config: VolcengineTTSConfig
  ) async throws {
    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    try AVAudioSession.sharedInstance().setActive(true)

    let client = VolcengineTTSClient(config: config)
    let cacheKey = activeCacheKey
      ?? TTSAudioCache.cacheKey(text: text, language: language, config: config)

    if let cached = await audioCache.pcm(forKey: cacheKey), !cached.isEmpty {
      activePCM = cached
      try playCachedPCM(cached, utteranceID: utteranceID, sampleRate: config.sampleRate)
      return
    }

    try streamPlayer.prepare(sampleRate: Double(config.sampleRate))

    let priority = TTSPreferenceStore.currentPlaybackPriority()
    let startupBytes = priority.startupBufferBytes
    var playbackStarted = false
    var accumulated = Data()
    let stream = client.synthesizeStream(text: text, language: language)
    for try await chunk in stream {
      try Task.checkCancellation()
      guard activeUtteranceID == utteranceID else { return }
      guard !chunk.isEmpty else { continue }

      accumulated.append(chunk)
      activePCM = accumulated

      switch priority {
      case .speed:
        try streamPlayer.appendPCM(chunk)
        if !playbackStarted, accumulated.count >= startupBytes {
          playbackStarted = true
          streamPlayer.start()
          state = .playing(utteranceID: utteranceID, engine: .volcengine)
        }
      case .smooth:
        // Hold audio until the stream finishes, then play the full buffer locally.
        break
      }
    }

    try Task.checkCancellation()
    guard activeUtteranceID == utteranceID else { return }
    guard !accumulated.isEmpty else {
      throw VolcengineTTSError.emptyAudio
    }

    // Persist only complete utterances so a cancelled stream never poisons cache.
    let evenCount = (accumulated.count / 2) * 2
    guard evenCount > 0 else {
      throw VolcengineTTSError.emptyAudio
    }
    let pcm = Data(accumulated.prefix(evenCount))
    activePCM = pcm
    try? await audioCache.store(pcm, forKey: cacheKey)

    switch priority {
    case .speed:
      // Chunks were already scheduled during the stream; only start if the
      // utterance was shorter than the startup buffer.
      streamPlayer.markStreamComplete()
      if !playbackStarted {
        streamPlayer.start()
        state = .playing(utteranceID: utteranceID, engine: .volcengine)
      }
    case .smooth:
      try playCachedPCM(pcm, utteranceID: utteranceID, sampleRate: config.sampleRate)
    }
  }

  private func playCachedPCM(_ pcm: Data, utteranceID: String, sampleRate: Int) throws {
    try streamPlayer.prepare(sampleRate: Double(sampleRate))
    try streamPlayer.appendPCM(pcm)
    streamPlayer.markStreamComplete()
    streamPlayer.start()
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
    utterance.voice = resolveSystemVoice(for: language)
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate
    state = .playing(utteranceID: utteranceID, engine: .system)
    synthesizer.speak(utterance)
  }

  private func resolveSystemVoice(for language: AppLanguage) -> AVSpeechSynthesisVoice? {
    let preferredID = TTSPreferenceStore.currentSystemVoiceIdentifier()
    if !preferredID.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: preferredID) {
      return voice
    }
    return preferredVoice(for: language)
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
    activeCacheKey = nil
    activeNormalizedText = nil
    activeLanguage = nil
    activeConfig = nil
    activePCM = Data()
    streamPlayer.stop()
    state = .idle
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
      // pauseSpeaking also reports cancel on some iOS versions — ignore while paused.
      if case .playing(let id, .system) = self.state {
        self.finishIfCurrent(id)
      }
    }
  }
}

/// Plays Volcengine s16le mono PCM with pause / resume support.
@MainActor
final class PCMStreamPlayer {
  var onFinished: (() -> Void)?

  private let engine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var format: AVAudioFormat?
  private var oddByteRemainder = Data()
  private var pendingBuffers = 0
  private var streamComplete = false
  private var isEngineRunning = false
  private var isPaused = false
  private var didNotifyFinished = false

  func prepare(sampleRate: Double) throws {
    stop()
    guard
      let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
      )
    else {
      throw VolcengineTTSError.invalidResponse
    }
    self.format = format
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    engine.prepare()
  }

  func appendPCM(_ chunk: Data) throws {
    guard let format else {
      throw VolcengineTTSError.invalidResponse
    }

    oddByteRemainder.append(chunk)
    let usableCount = (oddByteRemainder.count / 2) * 2
    guard usableCount > 0 else { return }

    // `prefix` / `dropFirst` can return Data with a non-zero startIndex; copy
    // into contiguous 0-based buffers before integer-range slicing.
    var frameData = Data(oddByteRemainder.prefix(usableCount))
    oddByteRemainder = Data(oddByteRemainder.dropFirst(usableCount))

    // Schedule modest slices so pause feels responsive on long cached audio.
    let maxBytesPerBuffer = 9_600  // 0.2s at 24 kHz s16le mono
    while !frameData.isEmpty {
      let length = min(maxBytesPerBuffer, frameData.count)
      let slice = Data(frameData.prefix(length))
      frameData = Data(frameData.dropFirst(length))
      try scheduleInt16PCM(slice, format: format)
    }
  }

  func start() {
    guard !isEngineRunning else {
      if isPaused {
        resume()
      }
      return
    }
    do {
      try engine.start()
      playerNode.play()
      isEngineRunning = true
      isPaused = false
    } catch {
      // Caller may fall back to system TTS.
    }
  }

  func pause() {
    guard isEngineRunning, !isPaused else { return }
    playerNode.pause()
    isPaused = true
  }

  func resume() {
    guard isEngineRunning, isPaused else { return }
    playerNode.play()
    isPaused = false
  }

  func markStreamComplete() {
    streamComplete = true
    oddByteRemainder.removeAll(keepingCapacity: false)
    notifyFinishedIfNeeded()
  }

  func stop() {
    if engine.isRunning || isEngineRunning {
      playerNode.stop()
      engine.stop()
    }
    if engine.attachedNodes.contains(playerNode) {
      engine.disconnectNodeOutput(playerNode)
      engine.detach(playerNode)
    }
    oddByteRemainder.removeAll(keepingCapacity: false)
    pendingBuffers = 0
    streamComplete = false
    isEngineRunning = false
    isPaused = false
    didNotifyFinished = false
    format = nil
  }

  private func scheduleInt16PCM(_ frameData: Data, format: AVAudioFormat) throws {
    let frameCount = frameData.count / 2
    guard frameCount > 0 else { return }
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frameCount)
      )
    else {
      throw VolcengineTTSError.invalidResponse
    }
    buffer.frameLength = AVAudioFrameCount(frameCount)

    frameData.withUnsafeBytes { raw in
      guard let source = raw.bindMemory(to: Int16.self).baseAddress,
        let destination = buffer.floatChannelData?[0]
      else { return }
      let scale = 1.0 / Float(Int16.max)
      for index in 0..<frameCount {
        destination[index] = Float(source[index]) * scale
      }
    }

    pendingBuffers += 1
    playerNode.scheduleBuffer(buffer) { [weak self] in
      Task { @MainActor in
        self?.bufferDidComplete()
      }
    }
  }

  private func bufferDidComplete() {
    pendingBuffers = max(0, pendingBuffers - 1)
    notifyFinishedIfNeeded()
  }

  private func notifyFinishedIfNeeded() {
    guard streamComplete, pendingBuffers == 0, !didNotifyFinished, !isPaused else { return }
    didNotifyFinished = true
    onFinished?()
  }
}
