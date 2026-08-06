import QuickLook
import SwiftUI
import UIKit

/// Temporary local file used as a Quick Look preview item.
struct SystemImagePreviewItem: Identifiable {
  let id = UUID()
  let fileURL: URL
}

/// Presents the system `QLPreviewController` modally so it keeps native chrome
/// (Done, share, pinch zoom) instead of embedding inside a SwiftUI stack.
struct SystemImageQuickLookPresenter: UIViewControllerRepresentable {
  @Binding var item: SystemImagePreviewItem?

  func makeCoordinator() -> Coordinator {
    Coordinator(item: $item)
  }

  func makeUIViewController(context: Context) -> UIViewController {
    context.coordinator.host
  }

  func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    context.coordinator.item = $item
    context.coordinator.syncPresentation()
  }

  final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    var item: Binding<SystemImagePreviewItem?>
    let host = UIViewController()
    private var presentedFileURL: URL?
    private weak var activePreview: QLPreviewController?

    init(item: Binding<SystemImagePreviewItem?>) {
      self.item = item
    }

    func syncPresentation() {
      if let fileURL = item.wrappedValue?.fileURL {
        guard presentedFileURL != fileURL else { return }
        presentPreview(fileURL: fileURL)
      } else if presentedFileURL != nil {
        dismissPreview()
      }
    }

    private func presentPreview(fileURL: URL) {
      presentedFileURL = fileURL
      let controller = QLPreviewController()
      controller.dataSource = self
      controller.delegate = self
      activePreview = controller

      if presenter() != nil {
        presentIfPossible(controller, fileURL: fileURL)
      } else {
        DispatchQueue.main.async { [weak self] in
          self?.presentIfPossible(controller, fileURL: fileURL)
        }
      }
    }

    private func presentIfPossible(_ controller: QLPreviewController, fileURL: URL) {
      guard presentedFileURL == fileURL else { return }
      guard let presenter = presenter() else { return }
      guard presenter.presentedViewController == nil else { return }
      presenter.present(controller, animated: true)
    }

    private func presenter() -> UIViewController? {
      if host.view.window != nil {
        return host
      }
      return UIApplication.shared.cultureLensTopViewController
    }

    private func dismissPreview() {
      presentedFileURL = nil
      if let activePreview, activePreview.presentingViewController != nil {
        activePreview.dismiss(animated: true)
      } else {
        presenter()?.dismiss(animated: true)
      }
      activePreview = nil
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(
      _ controller: QLPreviewController,
      previewItemAt index: Int
    ) -> any QLPreviewItem {
      (item.wrappedValue?.fileURL ?? presentedFileURL ?? URL(fileURLWithPath: "/")) as NSURL
    }

    func previewControllerDidDismiss(_ controller: QLPreviewController) {
      presentedFileURL = nil
      activePreview = nil
      if item.wrappedValue != nil {
        item.wrappedValue = nil
      }
    }
  }
}

enum SystemImagePreviewPreparer {
  enum PrepareError: Error {
    case emptyData
  }

  /// Reuses the app image cache, then writes a typed temp file for Quick Look.
  static func prepareTemporaryFile(from remoteURL: URL) async throws -> URL {
    let data = try await RemoteImageCache.shared.data(for: remoteURL)
    guard !data.isEmpty else { throw PrepareError.emptyData }

    let ext = fileExtension(for: remoteURL, data: data)
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("CultureLens-image-\(UUID().uuidString)")
      .appendingPathExtension(ext)
    try data.write(to: fileURL, options: .atomic)
    return fileURL
  }

  static func removeTemporaryFile(_ fileURL: URL?) {
    guard let fileURL else { return }
    try? FileManager.default.removeItem(at: fileURL)
  }

  private static func fileExtension(
    for remoteURL: URL,
    data: Data
  ) -> String {
    let pathExt = remoteURL.pathExtension.lowercased()
    let known = ["jpg", "jpeg", "png", "gif", "webp", "heic", "tif", "tiff", "bmp"]
    if known.contains(pathExt) {
      return pathExt == "jpeg" ? "jpg" : pathExt
    }

    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
    if data.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
    return "jpg"
  }
}

private extension UIApplication {
  var cultureLensTopViewController: UIViewController? {
    let scenes = connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
