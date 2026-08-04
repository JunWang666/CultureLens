//
//  CultureLensApp.swift
//  CultureLens
//
//  Created by 狗带菌 on 2026/7/27.
//

import SwiftUI
import SwiftData

@main
struct CultureLensApp: App {
    private let modelContainer: ModelContainer
    @State private var languageStore = AppLanguageStore()

    init() {
        modelContainer = CultureLensModelContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .modelContainer(modelContainer)
        .commands {
            AppTabCommands()
        }
    }
}

/// Shared SwiftData stack for scan history + knowledge progress.
/// Chat history is file-backed (`ChatHistoryStore`) and intentionally excluded —
/// embedding it here previously caused uncatchable `SIGABRT` on fetch/save.
enum CultureLensModelContainer {
    static let storeName = "CultureLensHistoryV3"

    static func make() -> ModelContainer {
        let schema = Schema([
            ScanHistoryRecord.self,
            KnowledgeProgressRecord.self,
        ])

        do {
            return try makeContainer(schema: schema, storeName: storeName)
        } catch {
            removeStoreFiles(named: storeName)
            do {
                return try makeContainer(schema: schema, storeName: storeName)
            } catch {
                fatalError("Unable to create CultureLens model container: \(error)")
            }
        }
    }

    private static func makeContainer(schema: Schema, storeName: String) throws -> ModelContainer {
        let configuration = ModelConfiguration(storeName, schema: schema)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func removeStoreFiles(named storeName: String) {
        let fileManager = FileManager.default
        guard
            let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
        else { return }

        let candidates = [
            appSupport.appending(path: storeName),
            appSupport.appending(path: "\(storeName).store"),
            appSupport.appending(path: "default.store"),
        ]

        for url in candidates {
            try? fileManager.removeItem(at: url)
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
            try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        }

        if let contents = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.lastPathComponent.contains(storeName) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
