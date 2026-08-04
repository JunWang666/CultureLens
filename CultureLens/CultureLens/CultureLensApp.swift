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
        do {
            let schema = Schema([
                ScanHistoryRecord.self,
                KnowledgeProgressRecord.self,
                ChatConversationRecord.self,
            ])
            let configuration = ModelConfiguration(
                "CultureLensHistoryV1",
                schema: schema
            )
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Unable to create CultureLens model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(languageStore)
                .environment(\.locale, languageStore.locale)
        }
        .modelContainer(modelContainer)
    }
}
