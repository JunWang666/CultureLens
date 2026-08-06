import SwiftUI
import UIKit

/// `AsyncImage`-compatible rendering backed by `RemoteImageCache`.
struct CachedAsyncImage<Content: View>: View {
  let url: URL?
  let transaction: Transaction
  @ViewBuilder let content: (AsyncImagePhase) -> Content

  @State private var phase: AsyncImagePhase = .empty

  init(
    url: URL?,
    transaction: Transaction = Transaction(),
    @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
  ) {
    self.url = url
    self.transaction = transaction
    self.content = content
  }

  var body: some View {
    content(phase)
      .task(id: url) {
        phase = .empty
        guard let url else { return }
        do {
          let data = try await RemoteImageCache.shared.data(for: url)
          try Task.checkCancellation()
          guard let image = UIImage(data: data) else {
            throw RemoteImageCache.CacheError.invalidResponse
          }
          withTransaction(transaction) {
            phase = .success(Image(uiImage: image))
          }
        } catch is CancellationError {
          return
        } catch {
          withTransaction(transaction) {
            phase = .failure(error)
          }
        }
      }
  }
}
