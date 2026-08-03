import CoreTransferable
import UniformTypeIdentifiers
import UIKit

/// Prefers a rendered card PNG when available; always offers readable text.
struct CultureCardShareItem: Transferable {
  let object: CultureObject
  let image: UIImage?

  var text: String {
    CultureCardShareRenderer.shareText(for: object)
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .png) { item in
      guard let data = item.image?.pngData() else {
        throw CocoaError(.fileReadCorruptFile)
      }
      return data
    }
    ProxyRepresentation(\.text)
  }
}
