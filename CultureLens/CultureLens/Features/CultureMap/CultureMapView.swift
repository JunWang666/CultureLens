import MapKit
import SwiftData
import SwiftUI

struct CultureMapView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "地图"
        case timeline = "时间线"
        var id: Self { self }
    }

    @Binding var path: [AppRoute]
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Picker("显示方式", selection: $displayMode) {
                        ForEach(DisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if records.isEmpty {
                        emptyState
                    } else if displayMode == .map {
                        historyMap
                    } else {
                        timeline
                    }
                }
                .padding(.horizontal, CultureTheme.pagePadding)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .cultureNavigationTitle("我的", showsBackButton: false)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.visitTrips) {
                    Label("文化回顾", systemImage: "book.pages")
                }
                .accessibilityIdentifier("profile.openReview")
            }
        }
        .onChange(of: selectedRecordID) { _, newValue in
            guard let newValue else { return }
            path.append(.history(newValue))
            selectedRecordID = nil
        }
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
        .frame(minHeight: 320)
    }

    @ViewBuilder
    private var historyMap: some View {
        if locatedRecords.isEmpty {
            ContentUnavailableView(
                "历史中没有位置",
                systemImage: "location.slash",
                description: Text("没有位置的扫描仍可在时间线中查看。")
            )
            .frame(minHeight: 320)
        } else {
            VStack(alignment: .leading, spacing: 14) {
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
                .frame(height: 390)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(CultureTheme.hairline, lineWidth: 1)
                }
                .accessibilityLabel("历史扫描地图，包含 \(locatedRecords.count) 个位置记录")

                Text("点击标记可直接查看对应的扫描记录。")
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }
        }
    }

    private var timeline: some View {
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
                    record.placeName ?? "未记录位置",
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
        CultureMapView(path: .constant([])) {}
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
}
