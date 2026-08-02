import Foundation

actor ScanMediaStore {
    static let shared = ScanMediaStore()

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func saveJPEG(_ data: Data, id: UUID) throws -> String {
        let directory = try scansDirectory()
        let filename = "\(id.uuidString.lowercased()).jpg"
        let url = directory.appending(path: filename)
        try data.write(to: url, options: [.atomic])
        return filename
    }

    func data(for relativePath: String?) -> Data? {
        guard let relativePath else { return nil }
        guard let directory = try? scansDirectory() else { return nil }
        return try? Data(contentsOf: directory.appending(path: relativePath))
    }

    func delete(relativePath: String?) throws {
        guard let relativePath else { return }
        let url = try scansDirectory().appending(path: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func scansDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appending(path: "CultureLens", directoryHint: .isDirectory)
            .appending(path: "Scans", directoryHint: .isDirectory)

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
