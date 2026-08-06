import Foundation

/// Structured output returned by the LLM, matching `v5.schema.json`
/// (Go `recognition.ProviderRecognition`). Unknown response fields are
/// ignored by the decoder.
nonisolated struct ProviderRecognition: Decodable, Sendable {
  var culturalElementKey: String
  var attractionKey: String
  var canonicalName: String
  var category: String
  var confidence: Double
  var summary: String
  var rationale: String
  var uncertainty: String
  var timePeriod: String
  var region: String
  var visualTags: [ProviderVisualTag]
  var alternatives: [ProviderCandidate]

  enum CodingKeys: String, CodingKey {
    case culturalElementKey = "cultural_element_key"
    case attractionKey = "attraction_key"
    case canonicalName = "canonical_name"
    case category
    case confidence
    case summary
    case rationale
    case uncertainty
    case timePeriod = "time_period"
    case region
    case visualTags = "visual_tags"
    case alternatives
  }
}

/// Freeform visual fallback tags from the recognition schema. They remain
/// separate from candidate IDs so they cannot affect knowledge resolution.
nonisolated struct ProviderVisualTag: Decodable, Sendable {
  var label: String
  var evidence: String
}

nonisolated struct ProviderCandidate: Decodable, Sendable {
  var culturalElementKey: String
  var canonicalName: String
  var category: String
  var confidence: Double
  var rationale: String

  enum CodingKeys: String, CodingKey {
    case culturalElementKey = "cultural_element_key"
    case canonicalName = "canonical_name"
    case category
    case confidence
    case rationale
  }
}
