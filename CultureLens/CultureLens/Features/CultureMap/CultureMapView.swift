import MapKit
import SwiftData
import SwiftUI

/// Scan footprint map + timeline + all knowledge-pack points of interest,
/// edge-to-edge under the system navigation toolbar.
struct CultureMapView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "地图足迹"
        case timeline = "时间线足迹"
        case pois = "兴趣点"
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .map: "map"
            case .timeline: "clock.arrow.circlepath"
            case .pois: "mappin.and.ellipse"
            }
        }
    }

    private enum BaseMapStyle: String, CaseIterable, Identifiable {
        case standard = "标准地图"
        case hybrid = "混合地图"
        case imagery = "卫星地图"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .standard: "map"
            case .hybrid: "square.3.layers.3d"
            case .imagery: "globe.asia.australia.fill"
            }
        }

        var mapStyle: MapStyle {
            switch self {
            case .standard:
                .standard(elevation: .realistic, showsTraffic: true)
            case .hybrid:
                .hybrid(elevation: .realistic, showsTraffic: true)
            case .imagery:
                .imagery(elevation: .realistic)
            }
        }
    }

    var showsBackButton: Bool = false
    let startScan: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    @State private var displayMode: DisplayMode = .map
    @State private var selectedRecordID: UUID?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var historyCamera: MapCamera?
    @State private var visibleSpan: MKCoordinateSpan?
    @State private var historySearchRegion: MKCoordinateRegion?
    @State private var clusterPicker: RecordCluster?

    @State private var knowledgeStore: KnowledgeStore?
    @State private var didAttemptStoreLoad = false
    @State private var poiCameraPosition: MapCameraPosition = .automatic
    @State private var poiCamera: MapCamera?
    @State private var poiSearchRegion: MKCoordinateRegion?

    @State private var baseMapStyle: BaseMapStyle = .standard
    @State private var is3DViewEnabled = false
    @State private var searchText = ""
    @State private var searchResults: [PlaceSearchResult] = []
    @State private var selectedSearchResult: PlaceSearchResult?
    @State private var isSearchingPlaces = false
    @State private var searchErrorMessage: String?
    @State private var isLocatingUser = false
    @State private var locationAlert: LocationAlert?
    @State private var locationProvider = LocationContextProvider()

    @FocusState private var isMapSearchFocused: Bool

    private var locatedRecords: [ScanHistoryRecord] {
        records.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// All pack attractions as map points ("所有兴趣点").
    private var poiPoints: [AttractionPoint] {
        knowledgeStore?.attractionPoints() ?? []
    }

    /// Element keys the user has already scanned — visited POIs.
    private var recordedElementKeys: Set<String> {
        Set(records.compactMap { $0.savedObject?.culturalElementKey })
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

    private struct PlaceSearchResult: Identifiable {
        let id = UUID()
        let mapItem: MKMapItem

        var name: String {
            mapItem.name ?? String(localized: "未命名地点")
        }

        var subtitle: String? {
            let title = mapItem.placemark.title
            guard let title, title != name else { return nil }
            return title
        }

        var coordinate: CLLocationCoordinate2D {
            mapItem.placemark.coordinate
        }
    }

    private struct LocationAlert: Identifiable {
        let id = UUID()
        let message: String
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
                if displayMode == .pois {
                    poiContent
                        .ignoresSafeArea()
                } else if displayMode == .map {
                    historyMap
                        .ignoresSafeArea()
                } else if records.isEmpty {
                    emptyState
                } else {
                    timelineScroll
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!showsBackButton)
        .toolbar {
            mapToolbarContent
        }
        .navigationDestination(item: $selectedRecordID) { id in
            ScanHistoryDetailView(recordID: id)
        }
        .task {
            guard knowledgeStore == nil, !didAttemptStoreLoad else { return }
            knowledgeStore = await KnowledgePackLoader.shared.store()
            didAttemptStoreLoad = true
        }
        .task(id: searchText) {
            await searchPlaces()
        }
        .alert(item: $locationAlert) { alert in
            Alert(
                title: Text("无法定位"),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    @ToolbarContentBuilder
    private var mapToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            locateUserToolbarButton
            displayModeMenu
        }
    }

    private var displayModeMenu: some View {
        Menu {
            Picker("显示方式", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Label(LocalizedStringKey(mode.rawValue), systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("底图", selection: $baseMapStyle) {
                ForEach(BaseMapStyle.allCases) { style in
                    Label(LocalizedStringKey(style.rawValue), systemImage: style.systemImage)
                        .tag(style)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Toggle(isOn: threeDimensionalViewBinding) {
                Label("3D 俯视", systemImage: "view.3d")
            }
        } label: {
            Image(systemName: displayMode.systemImage)
        }
        .accessibilityLabel("显示方式")
        .accessibilityValue(LocalizedStringKey(displayMode.rawValue))
    }

    private var threeDimensionalViewBinding: Binding<Bool> {
        Binding(
            get: { is3DViewEnabled },
            set: { set3DViewEnabled($0) }
        )
    }

    private var locateUserToolbarButton: some View {
        Button {
            locateUser()
        } label: {
            if isLocatingUser {
                ProgressView()
            } else {
                Image(systemName: "location.fill")
            }
        }
        .disabled(isLocatingUser)
        .accessibilityLabel("定位我的位置")
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
        Map(position: $mapPosition, selection: $selectedRecordID) {
            UserAnnotation()

            if let selectedSearchResult {
                Marker(
                    selectedSearchResult.name,
                    systemImage: "mappin.and.ellipse",
                    coordinate: selectedSearchResult.coordinate
                )
                .tint(.blue)
            }

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
        .mapStyle(baseMapStyle.mapStyle)
        .onMapCameraChange(frequency: .onEnd) { context in
            historyCamera = context.camera
            if displayMode == .map {
                is3DViewEnabled = context.camera.pitch > 1
            }
            visibleSpan = context.region.span
            historySearchRegion = context.region
        }
        .sheet(item: $clusterPicker) { cluster in
            clusterRecordList(cluster)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .topLeading) {
            if locatedRecords.isEmpty, selectedSearchResult == nil {
                noLocatedHistoryCallout
            }
        }
        .overlay(alignment: .bottomLeading) {
            mapSearchPanel
        }
        .accessibilityLabel("历史扫描地图，包含 \(locatedRecords.count) 个位置记录")
    }

    private var noLocatedHistoryCallout: some View {
        Label("还没有带位置的足迹", systemImage: "location.slash")
            .font(.callout.weight(.semibold))
            .foregroundStyle(CultureTheme.inkPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CultureTheme.surface, in: Capsule())
            .overlay {
                Capsule().stroke(CultureTheme.hairline, lineWidth: 1)
            }
            .safeAreaPadding(.leading, 12)
            .safeAreaPadding(.top, 12)
    }

    // MARK: - All points of interest (knowledge pack)

    @ViewBuilder
    private var poiContent: some View {
        if knowledgeStore == nil {
            if didAttemptStoreLoad {
                ContentUnavailableView(
                    "知识包暂不可用",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("知识包没有成功载入，兴趣点地图暂时不可用。")
                )
                .padding(CultureTheme.pagePadding)
            } else {
                ProgressView("正在载入兴趣点…")
            }
        } else if poiPoints.isEmpty {
            ContentUnavailableView(
                "知识包中没有兴趣点",
                systemImage: "mappin.slash",
                description: Text("当前知识包没有带位置信息的景点。")
            )
            .padding(CultureTheme.pagePadding)
        } else {
            poiMap
        }
    }

    private var poiMap: some View {
        Map(position: $poiCameraPosition) {
            UserAnnotation()

            if let selectedSearchResult {
                Marker(
                    selectedSearchResult.name,
                    systemImage: "mappin.and.ellipse",
                    coordinate: selectedSearchResult.coordinate
                )
                .tint(.blue)
            }

            ForEach(poiPoints) { point in
                Annotation(
                    "",
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    anchor: .bottom
                ) {
                    poiAnnotation(point)
                }
            }
        }
        .mapStyle(baseMapStyle.mapStyle)
        .onMapCameraChange(frequency: .onEnd) { context in
            poiCamera = context.camera
            if displayMode == .pois {
                is3DViewEnabled = context.camera.pitch > 1
            }
            poiSearchRegion = context.region
        }
        .overlay(alignment: .bottomLeading) {
            mapSearchPanel
        }
        .accessibilityLabel("知识包兴趣点地图，包含 \(poiPoints.count) 个景点")
    }

    private func set3DViewEnabled(_ enabled: Bool) {
        is3DViewEnabled = enabled

        let currentCamera: MapCamera?
        switch displayMode {
        case .map, .timeline:
            currentCamera = historyCamera ?? mapPosition.camera
        case .pois:
            currentCamera = poiCamera ?? poiCameraPosition.camera
        }
        guard var camera = currentCamera else { return }

        camera.pitch = enabled ? 55 : 0
        withAnimation {
            switch displayMode {
            case .map, .timeline:
                mapPosition = .camera(camera)
            case .pois:
                poiCameraPosition = .camera(camera)
            }
        }
    }

    private func locateUser() {
        guard !isLocatingUser else { return }
        isLocatingUser = true

        Task {
            defer { isLocatingUser = false }
            do {
                let place = try await locationProvider.requestBestPlace()
                let region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude: place.latitude,
                        longitude: place.longitude
                    ),
                    latitudinalMeters: 2_000,
                    longitudinalMeters: 2_000
                )
                withAnimation {
                    is3DViewEnabled = false
                    if displayMode == .pois {
                        poiCameraPosition = .region(region)
                    } else {
                        displayMode = .map
                        mapPosition = .region(region)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                locationAlert = LocationAlert(message: error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var mapSearchPanel: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                mapSearchPanelContent
            }
        } else {
            mapSearchPanelContent
        }
    }

    private var mapSearchPanelContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isMapSearchFocused, !trimmedSearchText.isEmpty {
                mapSearchResultsSurface
            }

            mapSearchField
        }
        .frame(width: 340)
        .safeAreaPadding(.leading, 12)
        .safeAreaPadding(.bottom, 12)
    }

    @ViewBuilder
    private var mapSearchField: some View {
        if #available(iOS 26.0, *) {
            mapSearchFieldContent
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            mapSearchFieldContent
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var mapSearchFieldContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.primary)

            TextField("搜索地点或地址", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isMapSearchFocused)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button("清除搜索", systemImage: "xmark.circle.fill") {
                    clearSearch()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    @ViewBuilder
    private var mapSearchResultsSurface: some View {
        if #available(iOS 26.0, *) {
            mapSearchResultsContent
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            mapSearchResultsContent
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
    }

    @ViewBuilder
    private var mapSearchResultsContent: some View {
        if isSearchingPlaces {
            Label("正在搜索…", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        } else if let searchErrorMessage {
            Label(searchErrorMessage, systemImage: "exclamationmark.triangle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        } else if searchResults.isEmpty {
            Label("未找到地点", systemImage: "mappin.slash")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(searchResults) { result in
                        Button {
                            selectSearchResult(result)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(CultureTheme.cinnabar)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .foregroundStyle(.primary)
                                    if let subtitle = result.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearSearch() {
        searchText = ""
        searchResults = []
        searchErrorMessage = nil
    }

    private func searchPlaces() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            searchErrorMessage = nil
            isSearchingPlaces = false
            return
        }

        isSearchingPlaces = true
        searchErrorMessage = nil

        do {
            try await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = [.address, .pointOfInterest]
            if let region = activeSearchRegion {
                request.region = region
            }

            let response = try await MKLocalSearch(request: request).start()
            guard !Task.isCancelled,
                  searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
            else { return }

            searchResults = response.mapItems.prefix(8).map {
                PlaceSearchResult(mapItem: $0)
            }
            isSearchingPlaces = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            searchErrorMessage = String(localized: "搜索暂时不可用")
            isSearchingPlaces = false
        }
    }

    private var activeSearchRegion: MKCoordinateRegion? {
        switch displayMode {
        case .map, .timeline:
            historySearchRegion
        case .pois:
            poiSearchRegion
        }
    }

    private func selectSearchResult(_ result: PlaceSearchResult) {
        selectedSearchResult = result

        let region = MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        withAnimation {
            if displayMode == .pois {
                poiCameraPosition = .region(region)
            } else {
                displayMode = .map
                mapPosition = .region(region)
            }
        }

        searchText = ""
        searchResults = []
        isMapSearchFocused = false
    }

    @ViewBuilder
    private func poiAnnotation(_ point: AttractionPoint) -> some View {
        let visited = point.culturalElementKey.map { recordedElementKeys.contains($0) } ?? false
        let label = VStack(spacing: 3) {
            Image(systemName: visited ? "checkmark.seal.fill" : "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(visited ? CultureTheme.cinnabar : CultureTheme.inkPrimary)
                .background(CultureTheme.canvas, in: Circle())
                .shadow(radius: 2, y: 1)
            Text(point.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CultureTheme.inkPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(visited ? "\(point.name)，已到访" : point.name)

        if let elementKey = point.culturalElementKey,
           knowledgeStore?.element(key: elementKey) != nil {
            NavigationLink(value: AppRoute.knowledgeElement(elementKey)) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开兴趣点详情")
        } else {
            label
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
