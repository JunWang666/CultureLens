import SwiftData
import SwiftUI

struct ScanCandidateDetailView: View {
    let session: ScanSession
    let candidate: RecognitionCandidate
    private let contentService: CultureContentService

    @Environment(\.modelContext) private var modelContext
    @State private var isSaving = false
    @State private var isSaved = false
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    DataImageView(data: session.imageData)
                        .frame(height: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    identity
                    introductionContent
                    candidateContext
                    saveAction
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("候选详情")
        .navigationBarTitleDisplayMode(.inline)
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

    private var identity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("附近景点候选", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            Text(object.canonicalName)
                .font(.cultureSerif(.largeTitle))
                .foregroundStyle(CultureTheme.inkPrimary)

            Text(object.category.rawValue)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text(introduction.name)
                                .font(.headline)
                                .foregroundStyle(CultureTheme.inkPrimary)
                            Text(introduction.introduction.plainText)
                                .font(.body)
                                .foregroundStyle(CultureTheme.inkSecondary)
                                .lineSpacing(5)
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
                    }
                }
            } else if displaySummary == nil {
                contentUnavailable("数据库中没有匹配到这个景点的现场介绍。")
            }

        case .failed(let message):
            contentUnavailable(message)
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

    private func contentUnavailable(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
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
            introductionState = .failed("本次扫描缺少位置或景点标识，无法读取现场介绍。")
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
                    isSaved ? "已加入扫描历史" : "确认候选并保存",
                    systemImage: isSaved ? "checkmark.circle.fill" : "map"
                )
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(isSaved ? .green : CultureTheme.cinnabar)
        .controlSize(.large)
        .disabled(isSaving || isSaved || displaySummary == nil)
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
                isSaved = true
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
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
