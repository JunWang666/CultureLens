import Foundation

/// Strips Markdown / citation noise so system TTS (and optional Volcengine
/// callers) read natural prose instead of symbols.
enum SpeechTextNormalizer {
  static func plainSpeechText(from source: String) -> String {
    var text = source.replacingOccurrences(of: "\r\n", with: "\n")

    // Fenced code blocks → drop contents.
    text = text.replacingOccurrences(
      of: #"```[\s\S]*?```"#,
      with: " ",
      options: .regularExpression
    )

    // Images ![alt](url) → alt text.
    text = text.replacingOccurrences(
      of: #"!\[([^\]]*)\]\([^)]+\)"#,
      with: "$1",
      options: .regularExpression
    )

    // Links [label](url) → label.
    text = text.replacingOccurrences(
      of: #"\[([^\]]+)\]\([^)]+\)"#,
      with: "$1",
      options: .regularExpression
    )

    // Headings / list / quote markers.
    text = text.replacingOccurrences(
      of: #"(?m)^#{1,6}\s+"#,
      with: "",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"(?m)^>\s+"#,
      with: "",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"(?m)^[\*\-\+]\s+"#,
      with: "",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"(?m)^\d+\.\s+"#,
      with: "",
      options: .regularExpression
    )

    // Emphasis / inline code.
    text = text.replacingOccurrences(of: "**", with: "")
    text = text.replacingOccurrences(of: "__", with: "")
    text = text.replacingOccurrences(of: "*", with: "")
    text = text.replacingOccurrences(of: "_", with: "")
    text = text.replacingOccurrences(of: "`", with: "")

    // Collapse whitespace.
    text = text.replacingOccurrences(
      of: #"[ \t]+\n"#,
      with: "\n",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"\n{3,}"#,
      with: "\n\n",
      options: .regularExpression
    )
    text = text.replacingOccurrences(
      of: #"[ \t]{2,}"#,
      with: " ",
      options: .regularExpression
    )

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
