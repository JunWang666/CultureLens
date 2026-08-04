import CoreTransferable
import UniformTypeIdentifiers
import UIKit

/// Prefers a rendered card PNG when available; always offers readable text.
struct CultureCardShareItem: Transferable {
  let object: CultureObject
  let image: UIImage?

  /// Explicitly nonisolated: `Transferable` export runs off the main actor,
  /// while this module defaults to `@MainActor` isolation.
  nonisolated var text: String {
    CultureCardShareRenderer.shareText(for: object)
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .png) { item in
      guard let data = item.image?.pngData() else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return data
    }
    // Closure form is clearer to SourceKit than `\.text` under default MainActor isolation.
    ProxyRepresentation(exporting: { item in
      CultureCardShareRenderer.shareText(for: item.object)
    })
  }
}
