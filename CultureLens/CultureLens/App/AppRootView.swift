import SwiftData
import SwiftUI

struct AppRootView: View {
    private let recognitionService: RecognitionService

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppLanguageStore.self) private var languageStore
    @State private var selectedTab: AppTab = .explore
    @State private var explorePath: [AppRoute] = []
    @State private var chatPath: [AppRoute] = []
    @State private var scanPath: [AppRoute] = []
    @State private var graphPath: [AppRoute] = []
    @State private var historyPath: [AppRoute] = []
    @State private var reviewPath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []
    @State private var morePath: [AppRoute] = []
    @State private var sessionStore = ScanSessionStore()
    @State private var knowledgeProgressStore = KnowledgeProgressStore()
    @State private var chatHistoryStore = ChatHistoryStore()
    @State private var knowledgeResourcesReady = false
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var historyRecords: [ScanHistoryRecord]

    private var showsSecondaryTabsInline: Bool {
        horizontalSizeClass == .regular
    }

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
                    ExploreHomeView()
                }
            }

            Tab(AppTab.chat.title, systemImage: AppTab.chat.systemImage, value: .chat) {
                appStack(path: $chatPath) {
                    AskCultureView(object: nil)
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
                    UserKnowledgeGraphView(onNavigate: { route in
                        graphPath.append(route)
                    })
                }
            }

            if showsSecondaryTabsInline {
                // Peer tabs so 足迹 / 文化回顾 / 设置 all stay in the top tab bar.
                historyTab
                reviewTab
                settingsTab
            } else {
                // iPhone: only a custom「更多」hub — do not register hidden secondary
                // tabs, or UIKit synthesizes its own More list.
                Tab(AppTab.more.title, systemImage: AppTab.more.systemImage, value: .more) {
                    appStack(path: $morePath) {
                        MoreHomeView()
                    }
                }
            }
        }
        // iPadOS: top tab bar that can expand into a sidebar when width allows.
        .tabViewStyle(.sidebarAdaptable)
        .defaultAdaptableTabBarPlacement(.tabBar)
        .focusedSceneValue(\.selectedAppTab, $selectedTab)
        .tint(CultureTheme.cinnabar)
        .environment(\.recognitionService, recognitionService)
        .environment(knowledgeProgressStore)
        .environment(chatHistoryStore)
        .environment(sessionStore)
        .environment(\.locale, languageStore.locale)
        .id("\(languageStore.language.rawValue)-\(knowledgeResourcesReady)")
        .onChange(of: horizontalSizeClass) { _, newValue in
            adaptSelection(for: newValue)
        }
        .onChange(of: selectedTab) { _, newValue in
            guard !showsSecondaryTabsInline, AppTab.secondaryTabs.contains(newValue) else {
                return
            }
            if let route = route(forSecondary: newValue) {
                morePath = [route]
            }
            selectedTab = .more
        }
        .task {
            knowledgeProgressStore.configure(modelContext: modelContext)
            if await KnowledgePackLoader.shared.store(fallback: nil) != nil {
                knowledgeResourcesReady = true
            }
        }
    }

    private var historyTab: some TabContent<AppTab> {
        Tab(AppTab.history.title, systemImage: AppTab.history.systemImage, value: .history) {
            appStack(path: $historyPath) {
                CultureMapView(showsBackButton: false) {
                    selectedTab = .scan
                }
            }
        }
    }

    private var reviewTab: some TabContent<AppTab> {
        Tab(AppTab.review.title, systemImage: AppTab.review.systemImage, value: .review) {
            appStack(path: $reviewPath) {
                VisitTripListView(showsBackButton: false)
            }
        }
    }

    private var settingsTab: some TabContent<AppTab> {
        Tab(AppTab.settings.title, systemImage: AppTab.settings.systemImage, value: .settings) {
            appStack(path: $settingsPath) {
                SettingsView(showsBackButton: false)
            }
        }
    }

    private func adaptSelection(for sizeClass: UserInterfaceSizeClass?) {
        if sizeClass == .compact {
            if AppTab.secondaryTabs.contains(selectedTab) {
                morePath = [route(forSecondary: selectedTab)].compactMap { $0 }
                selectedTab = .more
            }
        } else if selectedTab == .more {
            selectedTab = .history
            morePath = []
        }
    }

    private func route(forSecondary tab: AppTab) -> AppRoute? {
        switch tab {
        case .history: .footprint
        case .review: .visitTrips
        case .settings: .settings
        default: nil
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
                ?? knowledgeObject(id: id)
            {
                ScanResultView(knowledgeObject: object)
            } else {
                ContentUnavailableView("未找到对象", systemImage: "questionmark.circle")
            }
        case .concept(let id):
            if let concept = sessionStore.concept(id: id)
                ?? historyConcept(id: id)
                ?? SampleCultureData.concept(id: id)
            {
                ScanResultView(
                    knowledgeObject: CultureObject(
                        knowledgeConcept: concept,
                        elementID: id
                    )
                )
            } else {
                ContentUnavailableView(
                    "未找到文化关系", systemImage: "point.3.connected.trianglepath.dotted")
            }
        case .knowledgeElement(let id):
            if let element = KnowledgeStore.shared?.element(id: id) {
                ScanResultView(knowledgeObject: CultureObject(knowledgeElement: element))
            } else {
                ContentUnavailableView("知识节点暂不可用", systemImage: "externaldrive.badge.questionmark")
            }
        case .ask(let objectID):
            AskCultureView(
                object: sessionStore.object(id: objectID)
                    ?? historyObject(id: objectID)
                    ?? SampleCultureData.object(id: objectID)
                    ?? knowledgeObject(id: objectID),
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
            if let session = sessionStore.session(id: sessionID),
                let candidate = session.result.alternatives.first(
                    where: { $0.id == candidateID }
                )
            {
                ScanResultView(session: session, candidate: candidate)
            } else {
                ContentUnavailableView("候选已过期", systemImage: "clock.badge.exclamationmark")
            }
        case .history(let id):
            ScanHistoryDetailView(recordID: id)
        case .footprint:
            CultureMapView(showsBackButton: true) {
                selectedTab = .scan
            }
        case .visitTrips:
            VisitTripListView(showsBackButton: true)
        case .visitTrip(let id):
            VisitTripDetailView(tripID: id)
        case .themes:
            ThemeExploreListView()
        case .theme(let key):
            ThemeDetailView(themeKey: key)
        case .settings:
            SettingsView(showsBackButton: true)
        case .packEditor:
            PackEditorHomeView()
        case .packEditorDraft(let id):
            if let draft = KnowledgePackDraftStore.shared.draft(id: id) {
                PackEditorWorkspaceView(draft: draft)
            } else {
                ContentUnavailableView("草稿不存在", systemImage: "doc.badge.ellipsis")
            }
        }
    }

    private func historyObject(id: UUID) -> CultureObject? {
        historyRecords.lazy
            .compactMap(\.savedObject)
            .first { $0.id == id }
    }

    /// 知识库元素按确定性 id 解析为展示对象（图谱节点追问/详情兜底）。
    private func knowledgeObject(id: UUID) -> CultureObject? {
        KnowledgeStore.shared?.element(id: id).map(CultureObject.init(knowledgeElement:))
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
        .environment(AppLanguageStore())
}
