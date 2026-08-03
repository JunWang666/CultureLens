import Foundation

nonisolated struct LLMGatewayConfig: Sendable {
  let endpoint: URL
  let apiKey: String
  let model: String
  let timeout: TimeInterval

  /// Cloudflare AI Gateway (OpenAI-compatible chat/completions).
  static let `default` = LLMGatewayConfig(
    endpoint: URL(
      string:
        "https://gateway.ai.cloudflare.com/v1/b6fa8079d0ef1344774cb287040dc153/apps/compat/chat/completions"
    )!,
    apiKey: "cfut_P1crGwvtBy0SnlNeuJFZoej2j0b5rBLeAtSQNBo73539c0ba",
    model: "dynamic/culturelens",
    timeout: 55
  )

  /// Text Q&A and layered explanation / summary generation.
  static let chat = LLMGatewayConfig(
    endpoint: URL(
      string:
        "https://gateway.ai.cloudflare.com/v1/b6fa8079d0ef1344774cb287040dc153/apps/compat/chat/completions"
    )!,
    apiKey: "cfut_P1crGwvtBy0SnlNeuJFZoej2j0b5rBLeAtSQNBo73539c0ba",
    model: "dynamic/chat",
    timeout: 180
  )
}
