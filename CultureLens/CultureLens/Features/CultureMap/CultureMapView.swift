import ImageIO
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
    @State private var poiClusterPicker: POICluster?

    @State private var baseMapStyle: BaseMapStyle = .standard
    @State private var is3DViewEnabled = false
    @State private var showsHistoryPhotos = false
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

    /// A group of knowledge-pack points too close to tap individually.
    private struct POICluster: Identifiable {
        var points: [AttractionPoint]

        var id: UUID { points[0].id }

        var center: CLLocationCoordinate2D {
            let count = Double(points.count)
            return CLLocationCoordinate2D(
                latitude: points.map(\.latitude).reduce(0, +) / count,
                longitude: points.map(\.longitude).reduce(0, +) / count
            )
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

    /// Greedy screen-relative clustering: nearby records merge as the map zooms out.
    private var clusters: [RecordCluster] {
        let span = visibleSpan ?? boundingSpan
        var result: [RecordCluster] = []
        for record in locatedRecords {
            guard let latitude = record.latitude, let longitude = record.longitude else { continue }
            if let index = result.firstIndex(where: {
                coordinatesAreClose(
                    $0.center,
                    CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    in: span
                )
            }) {
                result[index].records.append(record)
            } else {
                result.append(RecordCluster(records: [record]))
            }
        }
        return result
    }

    /// The same clustering behavior is used for knowledge-pack points of interest.
    private var poiClusters: [POICluster] {
        let span = poiSearchRegion?.span
            ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        var result: [POICluster] = []
        for point in poiPoints {
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
            if let index = result.firstIndex(where: {
                coordinatesAreClose($0.center, coordinate, in: span)
            }) {
                result[index].points.append(point)
            } else {
                result.append(POICluster(points: [point]))
            }
        }
        return result
    }

    private func coordinatesAreClose(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D,
        in span: MKCoordinateSpan
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) < max(span.latitudeDelta / 10, 0.000_05)
            && abs(lhs.longitude - rhs.longitude) < max(span.longitudeDelta / 10, 0.000_05)
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
        .onChange(of: displayMode) {
            clusterPicker = nil
            poiClusterPicker = nil
        }
        .onChange(of: isMapSearchFocused) {
            guard isMapSearchFocused else { return }
            withAnimation {
                clusterPicker = nil
                poiClusterPicker = nil
            }
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

            Toggle(isOn: $showsHistoryPhotos) {
                Label("显示足迹照片", systemImage: "photo.on.rectangle")
            }

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
        Map(position: $mapPosition) {
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
                    Annotation(
                        "",
                        coordinate: CLLocationCoordinate2D(
                            latitude: latitude,
                            longitude: longitude
                        ),
                        anchor: .bottom
                    ) {
                        historyRecordAnnotation(record)
                    }
                } else {
                    Annotation("", coordinate: cluster.center, anchor: .center) {
                        clusterBadge(
                            count: cluster.records.count,
                            accessibilityLabel: "重叠的扫描记录"
                        ) {
                            handleClusterTap(cluster)
                        }
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

            ForEach(poiClusters) { cluster in
                if cluster.points.count == 1, let point = cluster.points.first {
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
                } else {
                    Annotation("", coordinate: cluster.center, anchor: .center) {
                        clusterBadge(
                            count: cluster.points.count,
                            accessibilityLabel: "重叠的兴趣点"
                        ) {
                            handlePOIClusterTap(cluster)
                        }
                    }
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
            if let clusterPicker {
                clusterRecordPickerSurface(clusterPicker)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let poiClusterPicker {
                poiClusterPickerSurface(poiClusterPicker)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if isMapSearchFocused, !trimmedSearchText.isEmpty {
                mapSearchResultsSurface
            }

            mapSearchField
        }
        .frame(width: 340)
        .safeAreaPadding(.leading, 12)
        .safeAreaPadding(.bottom, 12)
        .animation(.snappy, value: clusterPicker?.id)
        .animation(.snappy, value: poiClusterPicker?.id)
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

    private func historyRecordAnnotation(_ record: ScanHistoryRecord) -> some View {
        Button {
            clusterPicker = nil
            selectedRecordID = record.recordID
        } label: {
            VStack(spacing: 3) {
                historyRecordMarker(record)

                Text(record.canonicalName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(record.canonicalName)
        .accessibilityHint("打开历史扫描详情")
    }

    @ViewBuilder
    private func historyRecordMarker(_ record: ScanHistoryRecord) -> some View {
        if showsHistoryPhotos, record.imageRelativePath != nil {
            ScanMapThumbnail(
                relativePath: record.imageRelativePath,
                fallbackSymbol: symbol(for: record)
            )
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(radius: 3, y: 1)
        } else {
            Image(systemName: symbol(for: record))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(CultureTheme.cinnabar, in: Circle())
                .overlay {
                    Circle().stroke(.white, lineWidth: 2)
                }
                .shadow(radius: 2, y: 1)
        }
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

    private func clusterBadge(
        count: Int,
        accessibilityLabel: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill")
                Text("\(count)")
                    .monospacedDigit()
            }
            .font(.callout.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(CultureTheme.cinnabar, in: Capsule())
            .overlay {
                Capsule().stroke(.white, lineWidth: 2)
            }
            .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(count)")
        .accessibilityHint("轻点显示选择器")
    }

    /// 点按聚合点，在左下角搜索框上方展示该位置/附近的记录。
    private func handleClusterTap(_ cluster: RecordCluster) {
        isMapSearchFocused = false
        withAnimation {
            poiClusterPicker = nil
            clusterPicker = cluster
        }
    }

    private func handlePOIClusterTap(_ cluster: POICluster) {
        isMapSearchFocused = false
        withAnimation {
            clusterPicker = nil
            poiClusterPicker = cluster
        }
    }

    @ViewBuilder
    private func clusterRecordPickerSurface(_ cluster: RecordCluster) -> some View {
        if #available(iOS 26.0, *) {
            clusterRecordPickerContent(cluster)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            clusterRecordPickerContent(cluster)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
    }

    private func clusterRecordPickerContent(_ cluster: RecordCluster) -> some View {
        VStack(spacing: 0) {
            clusterPickerHeader(
                title: "该位置的扫描记录",
                count: cluster.records.count
            ) { dismissClusterPicker() }

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cluster.records) { record in
                        Button {
                            clusterPicker = nil
                            selectedRecordID = record.recordID
                        } label: {
                            historyClusterRow(record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    @ViewBuilder
    private func poiClusterPickerSurface(_ cluster: POICluster) -> some View {
        if #available(iOS 26.0, *) {
            poiClusterPickerContent(cluster)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            poiClusterPickerContent(cluster)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
    }

    private func poiClusterPickerContent(_ cluster: POICluster) -> some View {
        VStack(spacing: 0) {
            clusterPickerHeader(
                title: "兴趣点",
                count: cluster.points.count
            ) { dismissClusterPicker() }

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(cluster.points) { point in
                        if let elementKey = point.culturalElementKey,
                           knowledgeStore?.element(key: elementKey) != nil {
                            NavigationLink(value: AppRoute.knowledgeElement(elementKey)) {
                                poiClusterRow(point)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    poiClusterPicker = nil
                                }
                            )
                        } else {
                            poiClusterRow(point)
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
    }

    private func clusterPickerHeader(
        title: LocalizedStringKey,
        count: Int,
        close: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(CultureTheme.cinnabar)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.callout.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    private func dismissClusterPicker() {
        withAnimation(.snappy) {
            clusterPicker = nil
            poiClusterPicker = nil
        }
    }

    private func historyClusterRow(_ record: ScanHistoryRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: record))
                .foregroundStyle(CultureTheme.antiqueGold)
                .frame(width: 34, height: 34)
                .background(CultureTheme.inkPrimary, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.canonicalName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CultureTheme.inkPrimary)
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(CultureTheme.inkSecondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func poiClusterRow(_ point: AttractionPoint) -> some View {
        let visited = point.culturalElementKey.map { recordedElementKeys.contains($0) } ?? false
        return HStack(spacing: 12) {
            Image(systemName: visited ? "checkmark.seal.fill" : "mappin.circle.fill")
                .foregroundStyle(visited ? CultureTheme.cinnabar : CultureTheme.inkPrimary)
                .frame(width: 34, height: 34)
                .background(CultureTheme.canvas, in: RoundedRectangle(cornerRadius: 9))

            Text(point.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CultureTheme.inkPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if point.culturalElementKey != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityLabel(visited ? "\(point.name)，已到访" : point.name)
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

/// Loads only a small local preview so map annotations never retain full scan images.
private struct ScanMapThumbnail: View {
    let relativePath: String?
    let fallbackSymbol: String

    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    CultureTheme.cinnabar
                    Image(systemName: fallbackSymbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .task(id: relativePath) {
            thumbnail = nil
            guard let data = await ScanMediaStore.shared.data(for: relativePath) else { return }
            let prepared = await Task.detached(priority: .utility) {
                Self.downsampledImage(from: data)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = prepared
        }
    }

    private nonisolated static func downsampledImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            return nil
        }

        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        )
    }
}

#Preview {
    NavigationStack {
        CultureMapView(showsBackButton: false) {}
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
    .environment(AppLanguageStore())
}
