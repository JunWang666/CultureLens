import SwiftData
import SwiftUI

struct ScanResultView: View {
    let session: ScanSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var isSaved = false
    @State private var saveError: String?

    private var object: CultureObject {
        session.result.object
    }

    private var rationale: String {
        session.result.rationale
    }

    private var primaryObject: CultureObject {
        session.result.object
    }

    private var attractionCandidates: [RecognitionCandidate] {
        session.result.displayAttractionCandidates
    }

    private var currentResolutionStatus: String? {
        return session.result.resolutionStatus
    }

    var body: some View {
        ZStack {
            CulturePageBackground()

            SplitDetailLayout(topPadding: 16, bottomPadding: 40) { isWide in
                // 分栏布局下对象名提到左栏顶部（导航栏只显示“扫描结果”）
                if isWide {
                    Text(object.canonicalName)
                        .font(.cultureSerif(.largeTitle))
                        .foregroundStyle(CultureTheme.inkPrimary)
                }

                imageHeader(height: isWide ? 340 : 280)
                identity(showTitle: !isWide)
            } trailing: { _ in
                CultureRelationGraphView(object: primaryObject)
                alternatives
                evidenceCard
                saveAction
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // 两个坑：1) Button 和 Text 不能混在一个 HStack 里做 toolbar item（iOS 18+
        // 布局 bug，后面的子视图不渲染）；2) iOS 26 会把相邻 toolbar item 合并进同一个
        // 玻璃共享背景，标题需要用 sharedBackgroundVisibility(.hidden) 摘出来保持纯文本样式。
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    leadingTitle
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    leadingTitle
                }
            }
        }
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
    }

    // fixedSize 是必须的：iOS 26 toolbar item 可能分到比内容小的宽度导致文字被截断
    private var leadingTitle: some View {
        Text("扫描结果")
            .font(.headline)
            .foregroundStyle(CultureTheme.inkPrimary)
            .accessibilityIdentifier("result.title")
            .fixedSize()
    }

    private func imageHeader(height: CGFloat) -> some View {
        DataImageView(data: session.imageData)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topLeading) {
                Label(
                    session.isDemo ? "演示结果" : "视觉模型结果",
                    systemImage: session.isDemo ? "theatermasks" : "sparkles"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(14)
            }
    }

    private func identity(showTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(confidenceText, systemImage: confidenceSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.cinnabar)

            if currentResolutionStatus == "resolved" {
                Label("知识库已收录", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CultureTheme.inkSecondary)
            }

            // 单列布局下对象名显示在这里；分栏时已提到左栏顶部
            if showTitle {
                Text(object.canonicalName)
                    .font(.cultureSerif(.largeTitle))
                    .foregroundStyle(CultureTheme.inkPrimary)
            }

            Text(
                [object.category.rawValue, object.timePeriod, object.region]
                    .compactMap { $0 }
                    .joined(separator: " · ")
            )
            .font(.subheadline)
            .foregroundStyle(CultureTheme.inkSecondary)

            Text(object.summary)
                .font(.title3)
                .foregroundStyle(CultureTheme.inkPrimary)
                .lineSpacing(6)
        }
    }

    private var evidenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("判断依据", systemImage: "eye")
                .font(.headline)
                .foregroundStyle(CultureTheme.inkPrimary)

            Text(rationale)
                .font(.body)
                .foregroundStyle(CultureTheme.inkSecondary)
                .lineSpacing(5)

            if let uncertainty = session.result.uncertainty {
                Divider()
                Label("仍需确认", systemImage: "questionmark.circle")
                    .font(.headline)
                    .foregroundStyle(CultureTheme.cinnabar)
                Text(uncertainty)
                    .font(.subheadline)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }

            Divider()

            HStack {
                Label(
                    session.result.usedPlaceContext
                        ? (session.place?.displayName ?? "使用位置")
                        : "未使用位置",
                    systemImage: session.result.usedPlaceContext ? "location.fill" : "location.slash"
                )
                Spacer()
                Text(session.result.modelIdentifier)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(CultureTheme.inkSecondary)
        }
        .padding(20)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: CultureTheme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CultureTheme.cardRadius)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var alternatives: some View {
        if !attractionCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("附近景点候选")
                    .font(.cultureSerif(.title2))
                    .foregroundStyle(CultureTheme.inkPrimary)

                ForEach(attractionCandidates) { candidate in
                    NavigationLink(
                        value: AppRoute.scanCandidate(
                            sessionID: session.id,
                            candidateID: candidate.id
                        )
                    ) {
                        candidateRow(
                            name: candidate.canonicalName,
                            summary: candidate.informativeSummary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func candidateRow(
        name: String,
        summary: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(CultureTheme.inkPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CultureTheme.inkSecondary)
            }
            if let summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }
            Label("查看候选详情", systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CultureTheme.inkSecondary)
        }
        .padding(16)
        .background(
            CultureTheme.surface,
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
    }

    private var saveAction: some View {
        VStack(spacing: 12) {
            if isSaved {
                Label("已加入扫描历史", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                NavigationLink(value: AppRoute.object(object.id)) {
                    Label("阅读完整解释", systemImage: "book.pages")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CultureTheme.inkPrimary)
                .controlSize(.large)
            } else {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            "确认并保存到文化地图",
                            systemImage: "map"
                        )
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(CultureTheme.cinnabar)
                .controlSize(.large)
                .disabled(isSaving)
                .accessibilityIdentifier("result.save")
            }

            if session.isDemo {
                Text("演示结果会保存到本机历史，但不代表真实视觉识别。")
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var confidenceText: String {
        let prefix = object.confidence >= 0.8 ? "较高可信度" : "可能是"
        let percentage = object.confidence.formatted(
            .percent.precision(.fractionLength(0))
        )
        return "\(prefix) · \(percentage)"
    }

    private var confidenceSymbol: String {
        object.confidence >= 0.8 ? "checkmark.seal.fill" : "questionmark.diamond.fill"
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
                        selectedCandidateID: nil
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

#Preview {
    let result = RecognitionResult(
        id: UUID(),
        object: SampleCultureData.featured,
        alternatives: [],
        rationale: "根据木构件层叠与柱梁连接特征判断。",
        uncertainty: "仍需更清晰的屋檐整体照片确认时代。",
        modelIdentifier: "culturelens-sample-v1",
        usedPlaceContext: false,
        locationInfluence: nil
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
        ScanResultView(session: session)
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
