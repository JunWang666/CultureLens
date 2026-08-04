import MapKit
import SwiftData
import SwiftUI

/// Scan footprint map + timeline, edge-to-edge under the system navigation toolbar.
struct CultureMapView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "地图"
        case timeline = "时间线"
        var id: Self { self }
    }

    var showsBackButton: Bool = false
    let startScan: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    @State private var displayMode: DisplayMode = .map
    @State private var selectedRecordID: UUID?
    @State private var mapPosition: MapCameraPosition = .automatic

    private var locatedRecords: [ScanHistoryRecord] {
        records.filter { $0.latitude != nil && $0.longitude != nil }
    }

    var body: some View {
        ZStack {
            CulturePageBackground()
                .ignoresSafeArea()

            Group {
                if records.isEmpty {
                    emptyState
                } else if displayMode == .map {
                    historyMap
                        .ignoresSafeArea()
                } else {
                    timelineScroll
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!showsBackButton)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                displayModePicker
                    .frame(minWidth: 160, maxWidth: 220)
            }
        }
        .navigationDestination(item: $selectedRecordID) { id in
            ScanHistoryDetailView(recordID: id)
        }
    }

    private var displayModePicker: some View {
        Picker("显示方式", selection: $displayMode) {
            ForEach(DisplayMode.allCases) { mode in
                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("显示方式")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有扫描足迹", systemImage: "map")
        } description: {
            Text("完成一次扫描并确认结果，它会出现在这里。")
        } actions: {
            Button("开始扫描", action: startScan)
                .buttonStyle(.borderedProminent)
                .tint(CultureTheme.cinnabar)
        }
        .padding(CultureTheme.pagePadding)
    }

    @ViewBuilder
    private var historyMap: some View {
        if locatedRecords.isEmpty {
            ContentUnavailableView(
                "历史中没有位置",
                systemImage: "location.slash",
                description: Text("没有位置的扫描仍可在时间线中查看。")
            )
            .padding(CultureTheme.pagePadding)
        } else {
            Map(position: $mapPosition, selection: $selectedRecordID) {
                ForEach(locatedRecords) { record in
                    if let latitude = record.latitude, let longitude = record.longitude {
                        Marker(
                            record.canonicalName,
                            systemImage: symbol(for: record),
                            coordinate: CLLocationCoordinate2D(
                                latitude: latitude,
                                longitude: longitude
                            )
                        )
                        .tint(CultureTheme.cinnabar)
                        .tag(record.recordID)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .accessibilityLabel("历史扫描地图，包含 \(locatedRecords.count) 个位置记录")
        }
    }

    private var timelineScroll: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(records) { record in
                    NavigationLink(value: AppRoute.history(record.recordID)) {
                        historyCard(record)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("删除记录", role: .destructive) {
                            delete(record)
                        }
                    }
                }
            }
            .padding(.horizontal, CultureTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .safeAreaPadding(.top, 4)
    }

    private func historyCard(_ record: ScanHistoryRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol(for: record))
                .font(.title2)
                .foregroundStyle(CultureTheme.antiqueGold)
                .frame(width: 54, height: 54)
                .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(record.canonicalName)
                        .font(.headline)
                        .foregroundStyle(CultureTheme.inkPrimary)
                    Spacer()
                    Text(record.confidence, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(CultureTheme.cinnabar)
                }

                Text(record.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)

                Label(
                    record.placeName ?? String(localized: "未记录位置"),
                    systemImage: record.place == nil ? "location.slash" : "location"
                )
                .font(.caption)
                .foregroundStyle(CultureTheme.inkSecondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(CultureTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(CultureTheme.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开历史扫描详情")
    }

    private func symbol(for record: ScanHistoryRecord) -> String {
        switch ObjectCategory(rawValue: record.categoryRawValue) {
        case .architecture: "building.columns"
        case .artifact: "seal"
        case .pattern: "camera.macro"
        case .exhibit: "photo.artframe"
        case .space: "square.3.layers.3d"
        case .other, nil: "sparkles"
        }
    }

    private func delete(_ record: ScanHistoryRecord) {
        let path = record.imageRelativePath
        modelContext.delete(record)
        try? modelContext.save()
        Task {
            try? await ScanMediaStore.shared.delete(relativePath: path)
        }
    }
}

#Preview {
    NavigationStack {
        CultureMapView(showsBackButton: false) {}
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
    .environment(AppLanguageStore())
}
