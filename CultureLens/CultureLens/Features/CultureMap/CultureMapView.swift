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
    @State private var visibleSpan: MKCoordinateSpan?
    @State private var clusterPicker: RecordCluster?

    private var locatedRecords: [ScanHistoryRecord] {
        records.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// A group of records too close to tap individually at the current zoom.
    private struct RecordCluster: Identifiable {
        var records: [ScanHistoryRecord]

        var id: UUID { records[0].recordID }

        var center: CLLocationCoordinate2D {
            let count = Double(records.count)
            let latitude = records.compactMap(\.latitude).reduce(0, +) / count
            let longitude = records.compactMap(\.longitude).reduce(0, +) / count
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private var clusteringThreshold: CLLocationDegrees {
        let span = visibleSpan ?? boundingSpan
        return max(span.latitudeDelta, span.longitudeDelta) / 6
    }

    /// Fallback span derived from the records' bounding box before the camera reports one.
    private var boundingSpan: MKCoordinateSpan {
        let latitudes = locatedRecords.compactMap(\.latitude)
        let longitudes = locatedRecords.compactMap(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max()
        else {
            return MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        }
        return MKCoordinateSpan(
            latitudeDelta: max(maxLat - minLat, 0.01),
            longitudeDelta: max(maxLon - minLon, 0.01)
        )
    }

    /// Greedy clustering: records within a fraction of the visible span merge into one pin.
    private var clusters: [RecordCluster] {
        let threshold = clusteringThreshold
        var result: [RecordCluster] = []
        for record in locatedRecords {
            guard let latitude = record.latitude, let longitude = record.longitude else { continue }
            if let index = result.firstIndex(where: {
                abs($0.center.latitude - latitude) < threshold
                    && abs($0.center.longitude - longitude) < threshold
            }) {
                result[index].records.append(record)
            } else {
                result.append(RecordCluster(records: [record]))
            }
        }
        return result
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
                ForEach(clusters) { cluster in
                    if cluster.records.count == 1, let record = cluster.records.first,
                       let latitude = record.latitude, let longitude = record.longitude {
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
                    } else {
                        Annotation("", coordinate: cluster.center, anchor: .center) {
                            clusterBadge(cluster)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleSpan = context.region.span
            }
            .sheet(item: $clusterPicker) { cluster in
                clusterRecordList(cluster)
                    .presentationDetents([.medium, .large])
            }
            .accessibilityLabel("历史扫描地图，包含 \(locatedRecords.count) 个位置记录")
        }
    }

    private func clusterBadge(_ cluster: RecordCluster) -> some View {
        Button {
            handleClusterTap(cluster)
        } label: {
            Text("\(cluster.records.count)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(CultureTheme.cinnabar, in: Circle())
                .overlay {
                    Circle().stroke(.white, lineWidth: 2)
                }
                .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("重叠的扫描记录")
        .accessibilityHint("轻点查看记录列表")
    }

    /// 点按聚合点直接弹出该位置/附近的记录列表供选择。
    private func handleClusterTap(_ cluster: RecordCluster) {
        clusterPicker = cluster
    }

    private func clusterRecordList(_ cluster: RecordCluster) -> some View {
        NavigationStack {
            List(cluster.records) { record in
                Button {
                    clusterPicker = nil
                    // 等列表收起后再 push 详情，避免与 sheet 关闭动画冲突。
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        selectedRecordID = record.recordID
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: record))
                            .foregroundStyle(CultureTheme.antiqueGold)
                            .frame(width: 36, height: 36)
                            .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.canonicalName)
                                .font(.headline)
                                .foregroundStyle(CultureTheme.inkPrimary)
                            Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(CultureTheme.inkSecondary)
                        }
                    }
                }
            }
            .navigationTitle("该位置的扫描记录")
            .navigationBarTitleDisplayMode(.inline)
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
                    locationText(for: record),
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

    /// 坐标已记录但地名缺失时（如照片 EXIF 定位、逆地理编码失败）显示坐标兜底。
    private func locationText(for record: ScanHistoryRecord) -> String {
        if let placeName = record.placeName, !placeName.isEmpty {
            return placeName
        }
        if let latitude = record.latitude, let longitude = record.longitude {
            return String(localized: "已记录位置")
                + String(format: " %.3f, %.3f", latitude, longitude)
        }
        return String(localized: "未记录位置")
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
