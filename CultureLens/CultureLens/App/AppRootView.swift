import SwiftUI
import SwiftData

struct AppRootView: View {
    private let recognitionService: RecognitionService

    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .explore
    @State private var explorePath: [AppRoute] = []
    @State private var scanPath: [AppRoute] = []
    @State private var graphPath: [AppRoute] = []
    @State private var profilePath: [AppRoute] = []
    @State private var sessionStore = ScanSessionStore()
    @State private var knowledgeProgressStore = KnowledgeProgressStore()
    @State private var chatHistoryStore = ChatHistoryStore()
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var historyRecords: [ScanHistoryRecord]

    init(recognitionService: RecognitionService? = nil) {
        if let recognitionService {
            self.recognitionService = recognitionService
        } else if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            self.recognitionService = .sample
        } else {
            self.recognitionService = .configured()
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(AppTab.explore.title, systemImage: AppTab.explore.systemImage, value: .explore) {
                appStack(path: $explorePath) {
                    ExploreHomeView {
                        selectedTab = .scan
                    }
                }
            }

            Tab(AppTab.scan.title, systemImage: AppTab.scan.systemImage, value: .scan) {
                appStack(path: $scanPath) {
                    ScanView { session in
                        sessionStore.insert(session)
                        scanPath.append(.scanResult(session.id))
                    }
                }
            }

            Tab(AppTab.graph.title, systemImage: AppTab.graph.systemImage, value: .graph) {
                appStack(path: $graphPath) {
                    UserKnowledgeGraphView()
                }
            }

            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: .profile) {
                appStack(path: $profilePath) {
                    CultureMapView(path: $profilePath) {
                        selectedTab = .scan
                    }
                }
            }
        }
        .tint(CultureTheme.cinnabar)
        .environment(\.recognitionService, recognitionService)
        .environment(knowledgeProgressStore)
        .environment(chatHistoryStore)
        .environment(sessionStore)
        .task {
            knowledgeProgressStore.configure(modelContext: modelContext)
            chatHistoryStore.configure(modelContext: modelContext)
        }
    }

    private func appStack<Root: View>(
        path: Binding<[AppRoute]>,
        @ViewBuilder root: () -> Root
    ) -> some View {
        NavigationStack(path: path) {
            root()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .object(let id):
            if let object = sessionStore.object(id: id)
                ?? historyObject(id: id)
                ?? SampleCultureData.object(id: id)
            {
                ObjectDetailView(object: object)
            } else {
                ContentUnavailableView("未找到对象", systemImage: "questionmark.circle")
            }
        case .concept(let id):
            if let concept = sessionStore.concept(id: id)
                ?? historyConcept(id: id)
                ?? SampleCultureData.concept(id: id)
            {
                ConceptDetailView(concept: concept)
            } else {
                ContentUnavailableView("未找到文化关系", systemImage: "point.3.connected.trianglepath.dotted")
            }
        case .knowledgeElement(let key):
            if let concept = KnowledgeStore.shared?.cultureConcept(elementKey: key) {
                ConceptDetailView(concept: concept, elementKey: key)
            } else {
                ContentUnavailableView("知识节点暂不可用", systemImage: "externaldrive.badge.questionmark")
            }
        case .ask(let objectID):
            AskCultureView(
                object: sessionStore.object(id: objectID)
                    ?? historyObject(id: objectID)
                    ?? SampleCultureData.object(id: objectID),
                rationale: askRationale(for: objectID)
            )
        case .chat:
            AskCultureView(object: nil)
        case .scanResult(let id):
            if let session = sessionStore.session(id: id) {
                ScanResultView(session: session)
            } else {
                ContentUnavailableView("扫描结果已过期", systemImage: "clock.badge.exclamationmark")
            }
        case .scanCandidate(let sessionID, let candidateID):
            if
                let session = sessionStore.session(id: sessionID),
                let candidate = session.result.displayAttractionCandidates.first(
                    where: { $0.id == candidateID }
                )
            {
                ScanCandidateDetailView(session: session, candidate: candidate)
            } else {
                ContentUnavailableView("候选已过期", systemImage: "clock.badge.exclamationmark")
            }
        case .history(let id):
            ScanHistoryDetailView(recordID: id)
        }
    }

    private func historyObject(id: UUID) -> CultureObject? {
        historyRecords.lazy
            .compactMap(\.savedObject)
            .first { $0.id == id }
    }

    private func historyConcept(id: UUID) -> CultureConcept? {
        historyRecords.lazy
            .compactMap { $0.historySnapshot?.result.object ?? $0.legacyResultSnapshot?.object }
            .flatMap(\.concepts)
            .first { $0.id == id }
    }

    private func askRationale(for objectID: UUID) -> String {
        if let session = sessionStore.sessions.values.first(where: {
            $0.result.object.id == objectID
        }) {
            return session.result.rationale
        }
        if let record = historyRecords.first(where: { $0.cultureObjectID == objectID }),
           let rationale = record.historySnapshot?.result.rationale
            ?? record.legacyResultSnapshot?.rationale
        {
            return rationale
        }
        return ""
    }

}

#Preview {
    AppRootView()
}
