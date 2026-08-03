import Foundation
import SwiftStreamingMarkdown

/// Grows a Markdown snapshot sequence for `StreamedMarkdownView`.
final class GrowingMarkdownSource: @unchecked Sendable, StreamedMarkdownSource {
  private let continuation: AsyncStream<String>.Continuation
  private let stream: AsyncStream<String>
  private(set) var latest: String = ""

  var text: AsyncStream<String> { stream }

  init() {
    var continuation: AsyncStream<String>.Continuation!
    stream = AsyncStream { continuation = $0 }
    self.continuation = continuation
  }

  func yield(_ snapshot: String) {
    latest = snapshot
    continuation.yield(snapshot)
  }

  func finish() {
    continuation.finish()
  }
}
