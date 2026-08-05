import SwiftData
import SwiftUI

struct ScanCandidateDetailView: View {
    let session: ScanSession
    let candidate: RecognitionCandidate
    private let contentService: CultureContentService

    @Environment(\.modelContext) private var modelContext
    @Environment(KnowledgeProgressStore.self) private var knowledgeProgressStore
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var introductionState: CandidateIntroductionState = .idle

    init(
        session: ScanSession,
        candidate: RecognitionCandidate,
        contentService: CultureContentService = .live()
    ) {
        self.session = session
        self.candidate = candidate
        self.contentService = contentService
    }

    private var object: CultureObject {
        var result = candidate.cultureObject
        if let displaySummary {
            result.summary = displaySummary
        }
        return result
    }

    private var attractionElementKey: String? {
        candidate.attractionKey ?? object.culturalElementKey
    }

    private var objectElementKey: String? {
        object.culturalElementKey ?? KnowledgeStore.shared?.elementKey(for: object.id)
    }

    private var isInCultureGraph: Bool {
        knowledgeProgressStore.isInGraph(
            object.id,
            elementKey: attractionElementKey
        )
    }

    private var loadedIntroductions: [AttractionIntroductionRecommendation] {
        guard case .loaded(let introductions) = introductionState else {
            return []
        }
        return introductions
    }

    private var displaySummary: String? {
        candidate.informativeSummary
            ?? loadedIntroductions.lazy
                .map(\.introduction.plainText)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
    }

    private var additionalIntroductions: [AttractionIntroductionRecommendation] {
        var seen = Set<String>()
        if let displaySummary {
            seen.insert(normalized(displaySummary))
        }
        return loadedIntroductions.filter { introduction in
            let key = normalized(introduction.introduction.plainText)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            SplitDetailLayout(topPadding: 16, bottomPadding: 40) { isWide in
                // 分栏布局下对象名提到左栏顶部（导航栏只显示“候选详情”）
                if isWide {
                    LocalizedPackText(
                        source: object.canonicalName,
                        cacheNamespace: "element",
                        cacheKey: objectElementKey
                    )
                    .font(.cultureSerif(.largeTitle))
                    .foregroundStyle(CultureTheme.inkPrimary)
                }

                DataImageView(data: session.imageData)
                    .frame(height: isWide ? 340 : 280)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                identity(showTitle: !isWide)
            } trailing: { _ in
                introductionContent
                candidateContext
                saveAction
            }
        }
        .cultureNavigationTitle("候选详情")
        .alert(
            "无法保存",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("好", role: .cancel) {
                saveError = nil
            }
        } message: {
            Text(saveError ?? "")
        }
        .task(id: candidate.id) {
            await loadIntroductions()
        }
    }

    private func identity(showTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("附近景点候选", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            // 单列布局下对象名显示在这里；分栏时已提到左栏顶部
            if showTitle {
                LocalizedPackText(
                    source: object.canonicalName,
                    cacheNamespace: "element",
                    cacheKey: objectElementKey
                )
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)
            }

            Text(object.category.localizedTitle)
                .font(.subheadline)
                .foregroundStyle(CultureTheme.inkSecondary)

            if let displaySummary {
                Text(displaySummary)
                    .font(.title3)
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .lineSpacing(6)
            }
        }
    }

    @ViewBuilder
    private var introductionContent: some View {
        switch introductionState {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(displaySummary == nil ? "正在读取景点介绍…" : "正在读取更多现场知识…")
            }
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkSecondary)

        case .loaded:
            if !additionalIntroductions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("现场知识")
                        .font(.cultureSerif(.title2))
                        .foregroundStyle(CultureTheme.inkPrimary)

                    ForEach(additionalIntroductions) { introduction in
                        LocalizedIntroductionCard(introduction: introduction)
                    }
                }
            } else if displaySummary == nil {
                contentUnavailable("数据库中没有匹配到这个景点的现场介绍。")
            }

        case .failed(let message):
            contentUnavailableText(message)
        }
    }

    private var candidateContext: some View {
        Label(
            "根据本次扫描位置列为候选，尚未由画面确认。",
            systemImage: "location.fill"
        )
        .font(.subheadline)
        .foregroundStyle(CultureTheme.inkSecondary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CultureTheme.surface,
            in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        )
    }

    private func contentUnavailable(_ message: LocalizedStringKey) -> some View {
        contentUnavailableBody(Label(message, systemImage: "exclamationmark.circle"))
    }

    /// Runtime strings arrive already localized (or from the service); show verbatim.
    private func contentUnavailableText(_ message: String) -> some View {
        contentUnavailableBody(Label(message, systemImage: "exclamationmark.circle"))
    }

    private func contentUnavailableBody(_ label: some View) -> some View {
        label
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkSecondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                CultureTheme.surface,
                in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
            )
    }

    @MainActor
    private func loadIntroductions() async {
        guard
            let place = session.place,
            let attractionKey = candidate.attractionKey
        else {
            introductionState = .failed(String(localized: "本次扫描缺少位置或景点标识，无法读取现场介绍。"))
            return
        }

        introductionState = .loading
        do {
            let response = try await contentService.nearbyRecommendations(
                place.latitude,
                place.longitude,
                50_000,
                20
            )
            introductionState = .loaded(
                response.introductions.filter {
                    $0.attraction.key == attractionKey
                }
            )
        } catch is CancellationError {
            return
        } catch {
            introductionState = .failed(error.localizedDescription)
        }
    }

    private func normalized(_ value: String) -> String {
        value.filter { !$0.isWhitespace }.lowercased()
    }

    private var saveAction: some View {
        Button {
            save()
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Label(
                    isInCultureGraph ? LocalizedStringKey("已加入文化图谱") : "确认候选并加入文化图谱",
                    systemImage: isInCultureGraph
                        ? "checkmark.circle.fill"
                        : "point.3.connected.trianglepath.dotted"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(isInCultureGraph ? .green : CultureTheme.cinnabar)
        .controlSize(.large)
        .disabled(isSaving || isInCultureGraph || displaySummary == nil)
        .accessibilityIdentifier("candidate.save")
    }

    private func save() {
        isSaving = true
        Task {
            do {
                let path = try await ScanMediaStore.shared.saveJPEG(
                    session.imageData,
                    id: session.id
                )
                let place = session.place
                let snapshotData = try JSONEncoder().encode(
                    ScanHistorySnapshot(
                        result: session.result,
                        selectedObject: object,
                        selectedCandidateID: candidate.id
                    )
                )
                let record = ScanHistoryRecord(
                    recordID: session.id,
                    createdAt: session.createdAt,
                    cultureObjectID: object.id,
                    canonicalName: object.canonicalName,
                    categoryRawValue: object.category.rawValue,
                    summary: object.summary,
                    timePeriod: object.timePeriod,
                    region: object.region,
                    confidence: object.confidence,
                    latitude: place?.latitude,
                    longitude: place?.longitude,
                    placeName: place?.displayName,
                    imageRelativePath: path,
                    modelIdentifier: session.result.modelIdentifier,
                    resultSnapshotData: snapshotData
                )
                modelContext.insert(record)
                try modelContext.save()
                knowledgeProgressStore.setLevel(
                    .contact,
                    for: object.id,
                    source: .manual,
                    elementKey: attractionElementKey
                )
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}

private enum CandidateIntroductionState {
    case idle
    case loading
    case loaded([AttractionIntroductionRecommendation])
    case failed(String)
}

/// On-site introduction card that translates the pack name + body into the
/// active app language, showing a skeleton while a translation is in flight.
private struct LocalizedIntroductionCard: View {
    let introduction: AttractionIntroductionRecommendation

    @Environment(AppLanguageStore.self) private var languageStore
    @State private var resolvedName: String?
    @State private var resolvedText: String?

    private var showsSourceDirectly: Bool {
        languageStore.language.isKnowledgeSource
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSourceDirectly {
                sourceContent
            } else if let resolvedName, let resolvedText {
                Text(resolvedName)
                    .font(.headline)
                    .foregroundStyle(CultureTheme.inkPrimary)
                RichTextBlocksView(document: .plain(resolvedText))
            } else {
                SkeletonLine(height: 14, widthFraction: 0.45)
                SkeletonTextBlock(widthFractions: [1.0, 0.9])
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CultureTheme.surface,
            in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .task(id: "\(introduction.key)|\(languageStore.language.rawValue)") {
            await reload()
        }
    }

    private var sourceContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(introduction.name)
                .font(.headline)
                .foregroundStyle(CultureTheme.inkPrimary)
            RichTextBlocksView(document: introduction.introduction)
        }
    }

    @MainActor
    private func reload() async {
        resolvedName = nil
        resolvedText = nil
        guard !languageStore.language.isKnowledgeSource else { return }
        let translated = await KnowledgeTranslationService.shared.localizedNameAndText(
            cacheNamespace: "introduction",
            key: introduction.key,
            sourceName: introduction.name,
            sourceText: introduction.introduction.plainText,
            language: languageStore.language
        )
        guard !Task.isCancelled else { return }
        resolvedName = translated.name
        resolvedText = translated.text
    }
}

#Preview {
    let candidate = RecognitionCandidate(
        id: UUID(),
        attractionKey: "three-pools-mirroring-moon",
        canonicalName: "三潭印月",
        category: .space,
        confidence: 0,
        rationale: "根据当前位置列出的附近景点，仍需结合画面确认。",
        summary: "三潭印月以湖中石塔、圆孔与月影形成独特的观看体验。",
        resolutionStatus: "attraction"
    )
    let result = RecognitionResult(
        id: UUID(),
        object: SampleCultureData.featured,
        alternatives: [candidate],
        rationale: "根据画面判断。",
        modelIdentifier: "preview",
        usedPlaceContext: true
    )
    let session = ScanSession(
        id: result.id,
        imageData: Data(),
        result: result,
        place: nil,
        createdAt: Date(),
        isDemo: true
    )

    NavigationStack {
        ScanCandidateDetailView(
            session: session,
            candidate: candidate,
            contentService: CultureContentService { _, _, _, _ in
                NearbyRecommendationsResponse(
                    requestedLocation: RequestedRecommendationLocation(
                        latitude: 30.25,
                        longitude: 120.15,
                        radiusMeters: 50_000
                    ),
                    totalMatches: 1,
                    introductions: []
                )
            }
        )
    }
    .environment(KnowledgeProgressStore())
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
