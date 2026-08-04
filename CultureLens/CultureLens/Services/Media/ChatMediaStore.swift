import Foundation

actor ChatMediaStore {
  static let shared = ChatMediaStore()

  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func saveJPEG(_ data: Data, id: UUID = UUID()) throws -> String {
    let directory = try chatsDirectory()
    let filename = "\(id.uuidString.lowercased()).jpg"
    let url = directory.appending(path: filename)
    try data.write(to: url, options: [.atomic])
    return filename
  }

  func data(for relativePath: String?) -> Data? {
    guard let relativePath else { return nil }
    guard let directory = try? chatsDirectory() else { return nil }
    return try? Data(contentsOf: directory.appending(path: relativePath))
  }

  func delete(relativePath: String?) throws {
    guard let relativePath else { return }
    let url = try chatsDirectory().appending(path: relativePath)
    guard fileManager.fileExists(atPath: url.path) else { return }
    try fileManager.removeItem(at: url)
  }

  func deleteAll(relativePaths: [String]) {
    for path in relativePaths {
      try? delete(relativePath: path)
    }
  }

  private func chatsDirectory() throws -> URL {
    let applicationSupport = try fileManager.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = applicationSupport
      .appending(path: "CultureLens", directoryHint: .isDirectory)
      .appending(path: "Chats", directoryHint: .isDirectory)

    try fileManager.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
