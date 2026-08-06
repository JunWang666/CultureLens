import ImageIO
import MapKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Scan footprint map + all knowledge-pack points of interest,
/// edge-to-edge under the system navigation toolbar.
/// Chronological timeline lives under the Review tab (`ScanTimelineView`).
struct CultureMapView: View {
    enum DisplayMode: String, CaseIterable, Identifiable {
        case map = "地图足迹"
        case pois = "兴趣点"
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .map: "map"
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

    @Query(sort: \ScanHistoryRecord.createdAt, order: .reverse)
    private var records: [ScanHistoryRecord]

    @State private var displayMode: DisplayMode = .map
    @State private var selectedRecordID: UUID?
    /// Prefer the user until the first explicit 2 km framing resolves.
    @State private var mapPosition: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )
    @State private var mapCamera: MapCamera?
    @State private var visibleSpan: MKCoordinateSpan?
    @State private var mapSearchRegion: MKCoordinateRegion?
    @State private var didApplyInitialUserLocation = false
    @State private var clusterPicker: RecordCluster?

    @State private var knowledgeStore: KnowledgeStore?
    @State private var didAttemptStoreLoad = false
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

    @State private var importedTracks: [ImportedTrack] = []
    @State private var showsImportedTracks = true
    @State private var isChoosingTrackFiles = false
    @State private var isImportingTracks = false
    @State private var trackImportSheet: TrackImportSheet?
    @State private var trackImportNotice: TrackImportNotice?
    @State private var pendingTrackDeletion: ImportedTrack?

    @FocusState private var isMapSearchFocused: Bool

    private var locatedRecords: [ScanHistoryRecord] {
        records.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// All pack attractions as map points ("所有兴趣点").
    private var poiPoints: [AttractionPoint] {
        knowledgeStore?.attractionPoints() ?? []
    }

    /// Element UUIDs the user has already scanned — visited POIs.
    private var recordedElementIDs: Set<UUID> {
        Set(records.compactMap { $0.savedObject?.culturalElementID })
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

    private struct TrackImportNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private enum TrackImportSheet: String, Identifiable {
        case fitness

        var id: String { rawValue }
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
        // The shared camera can be zoomed out to a whole GPX track (or farther)
        // before POI mode is selected. Letting that very large span drive the
        // proximity threshold would merge unrelated sites across the city into
        // one stack. Keep clustering responsive while nearby, but cap its
        // effective span so a distant footprint view does not over-cluster POIs.
        let visibleSpan = visibleSpan
            ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        let clusteringSpan = MKCoordinateSpan(
            latitudeDelta: min(visibleSpan.latitudeDelta, 0.05),
            longitudeDelta: min(visibleSpan.longitudeDelta, 0.05)
        )
        var result: [POICluster] = []
        for point in poiPoints {
            let coordinate = CLLocationCoordinate2D(
                latitude: point.latitude,
                longitude: point.longitude
            )
            if let index = result.firstIndex(where: {
                coordinatesAreClose($0.center, coordinate, in: clusteringSpan)
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

            sharedMap
                .ignoresSafeArea()
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
        .task {
            importedTracks = (try? await ImportedTrackStore.shared.load()) ?? []
        }
        .task {
            await applyInitialUserLocationIfNeeded()
        }
        .task(id: searchText) {
            await searchPlaces()
        }
        .fileImporter(
            isPresented: $isChoosingTrackFiles,
            allowedContentTypes: [.gpx, .xml],
            allowsMultipleSelection: true,
            onCompletion: handleTrackFileSelection
        )
        .sheet(item: $trackImportSheet) { destination in
            switch destination {
            case .fitness:
                FitnessWorkoutImportView(
                    importedSourceIdentifiers: fitnessWorkoutSourceIdentifiers,
                    onImported: handleFitnessTracksImported
                )
            }
        }
        .alert(item: $locationAlert) { alert in
            Alert(
                title: Text("无法定位"),
                message: Text(alert.message),
                dismissButton: .default(Text("好"))
            )
        }
        .alert(item: $trackImportNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "删除运动轨迹？",
            isPresented: pendingTrackDeletionBinding,
            presenting: pendingTrackDeletion
        ) { track in
            Button("删除“\(track.name)”", role: .destructive) {
                deleteImportedTrack(track)
            }
            Button("取消", role: .cancel) {}
        } message: { track in
            if track.sourceKind == .appleFitness {
                Text("轨迹副本将从 App 中移除，但不会删除 Fitness 或健康中的原记录。")
            } else {
                Text("轨迹将从 App 中移除，但不会删除原来的 GPX 文件。")
            }
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

    private var importTrackMenu: some View {
        Menu {
            Button {
                trackImportSheet = .fitness
            } label: {
                Label("从 Fitness 导入", systemImage: "heart.fill")
            }

            Button {
                isChoosingTrackFiles = true
            } label: {
                Label("从文件导入 GPX", systemImage: "doc.badge.plus")
            }
        } label: {
            Label("导入运动轨迹", systemImage: "doc.badge.plus")
        }
        .disabled(isImportingTracks)
    }

    private var displayModeMenu: some View {
        Menu {
            Picker("显示方式", selection: displayModeBinding) {
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

            Divider()

            importTrackMenu

            if !importedTracks.isEmpty {
                Toggle(isOn: $showsImportedTracks) {
                    Label("显示运动轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

                Menu {
                    ForEach(importedTracks) { track in
                        Menu {
                            Button {
                                focus(on: track)
                            } label: {
                                Label("在地图上显示", systemImage: "scope")
                            }

                            Button(role: .destructive) {
                                pendingTrackDeletion = track
                            } label: {
                                Label("删除轨迹", systemImage: "trash")
                            }
                        } label: {
                            Label(track.name, systemImage: "figure.run")
                        }
                    }
                } label: {
                    Label("已导入轨迹（\(importedTracks.count)）", systemImage: "figure.run")
                }
            }
        } label: {
            Image(systemName: displayMode.systemImage)
        }
        .accessibilityLabel("显示方式")
        .accessibilityValue(LocalizedStringKey(displayMode.rawValue))
    }

    /// Pinning `.automatic` to the camera currently on screen prevents MapKit
    /// from reframing when the annotation collection changes between map modes.
    private var displayModeBinding: Binding<DisplayMode> {
        Binding(
            get: { displayMode },
            set: { newValue in
                guard let camera = mapCamera ?? mapPosition.camera else {
                    displayMode = newValue
                    return
                }

                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    mapPosition = .camera(camera)
                    displayMode = newValue
                }
            }
        )
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

    private var sharedMap: some View {
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

            if displayMode == .map, showsImportedTracks {
                // Draw every outline first so later tracks cannot cover another
                // track's orange center line at intersections.
                ForEach(importedTracks) { track in
                    ForEach(track.segments) { segment in
                        MapPolyline(coordinates: segment.sampledPoints().map(\.coordinate))
                            .stroke(
                                .black.opacity(0.9),
                                style: StrokeStyle(
                                    lineWidth: 7,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                }

                ForEach(importedTracks) { track in
                    ForEach(track.segments) { segment in
                        MapPolyline(coordinates: segment.sampledPoints().map(\.coordinate))
                            .stroke(
                                .orange,
                                style: StrokeStyle(
                                    lineWidth: 4,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                }
            }

            // Keep history and POI annotations in separate, stable builder
            // slots. This prevents MapKit from reusing an annotation view from
            // the previous mode at the new collection's coordinate.
            ForEach(displayMode == .map ? clusters : []) { cluster in
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

            ForEach(displayMode == .pois && knowledgeStore != nil ? poiClusters : []) { cluster in
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
            mapCamera = context.camera
            is3DViewEnabled = context.camera.pitch > 1
            visibleSpan = context.region.span
            mapSearchRegion = context.region
        }
        .overlay(alignment: .topLeading) {
            if displayMode == .map,
               locatedRecords.isEmpty,
               (!showsImportedTracks || importedTracks.isEmpty),
               selectedSearchResult == nil {
                mapStatusCallout("还没有带位置的足迹", systemImage: "location.slash")
            } else if displayMode == .pois {
                poiAvailabilityCallout
            }
        }
        .overlay(alignment: .bottomLeading) {
            mapSearchPanel
        }
        .accessibilityLabel(
            displayMode == .pois
                ? Text("知识包兴趣点地图，包含 \(poiPoints.count) 个景点")
                : Text(
                    "历史扫描地图，包含 \(locatedRecords.count) 个位置记录和 \(importedTracks.count) 条运动轨迹"
                )
        )
    }

    @ViewBuilder
    private var poiAvailabilityCallout: some View {
        if knowledgeStore == nil {
            if didAttemptStoreLoad {
                mapStatusCallout(
                    "知识包暂不可用",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            } else {
                mapStatusCallout("正在载入兴趣点…", systemImage: "arrow.clockwise")
            }
        } else if poiPoints.isEmpty {
            mapStatusCallout("知识包中没有兴趣点", systemImage: "mappin.slash")
        }
    }

    private func mapStatusCallout(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
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

    private func set3DViewEnabled(_ enabled: Bool) {
        is3DViewEnabled = enabled

        guard var camera = mapCamera ?? mapPosition.camera else { return }

        camera.pitch = enabled ? 55 : 0
        withAnimation {
            mapPosition = .camera(camera)
        }
    }

    /// Centers the shared map on the user at a ~2 km visible width.
    private func locateUser(showsErrorAlert: Bool = true) {
        guard !isLocatingUser else { return }
        isLocatingUser = true

        Task {
            defer { isLocatingUser = false }
            await centerMapOnUserLocation(animated: true, showsErrorAlert: showsErrorAlert)
        }
    }

    /// One-shot framing when the footprint tab first appears.
    private func applyInitialUserLocationIfNeeded() async {
        guard !didApplyInitialUserLocation else { return }
        didApplyInitialUserLocation = true
        guard !isLocatingUser else { return }
        isLocatingUser = true
        defer { isLocatingUser = false }
        await centerMapOnUserLocation(animated: false, showsErrorAlert: false)
    }

    private func centerMapOnUserLocation(animated: Bool, showsErrorAlert: Bool) async {
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
            let apply = {
                is3DViewEnabled = false
                mapPosition = .region(region)
            }
            if animated {
                withAnimation {
                    apply()
                }
            } else {
                apply()
            }
        } catch is CancellationError {
            return
        } catch {
            if showsErrorAlert {
                locationAlert = LocationAlert(message: error.localizedDescription)
            }
        }
    }

    private var pendingTrackDeletionBinding: Binding<Bool> {
        Binding(
            get: { pendingTrackDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingTrackDeletion = nil
                }
            }
        )
    }

    private var fitnessWorkoutSourceIdentifiers: Set<String> {
        Set(
            importedTracks.compactMap { track in
                guard track.sourceKind == .appleFitness else { return nil }
                return track.sourceIdentifier
            }
        )
    }

    private func handleFitnessTracksImported(_ tracks: [ImportedTrack]) {
        guard !tracks.isEmpty else { return }
        let importedIDs = Set(tracks.map(\.id))
        importedTracks = tracks + importedTracks.filter { !importedIDs.contains($0.id) }
        showsImportedTracks = true
        if let lastImported = tracks.last {
            focus(on: lastImported)
        }

        let pointCount = tracks.reduce(0) { $0 + $1.pointCount }
        trackImportNotice = TrackImportNotice(
            title: String(localized: "轨迹已导入"),
            message: String(
                localized: "已从 Fitness 保存 \(tracks.count) 条运动轨迹，共 \(pointCount) 个轨迹点。"
            )
        )
    }

    private func handleTrackFileSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case .failure(let error):
            trackImportNotice = TrackImportNotice(
                title: String(localized: "无法导入轨迹"),
                message: error.localizedDescription
            )
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImportingTracks = true

            Task {
                var successes: [ImportedTrack] = []
                var failures: [String] = []

                for url in urls {
                    do {
                        successes.append(try await ImportedTrackStore.shared.importGPX(from: url))
                    } catch {
                        failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
                    }
                }

                if !successes.isEmpty {
                    importedTracks = (try? await ImportedTrackStore.shared.load())
                        ?? (successes + importedTracks)
                    showsImportedTracks = true
                    if let lastImported = successes.last {
                        focus(on: lastImported)
                    }
                }

                isImportingTracks = false
                if failures.isEmpty {
                    let pointCount = successes.reduce(0) { $0 + $1.pointCount }
                    trackImportNotice = TrackImportNotice(
                        title: String(localized: "轨迹已导入"),
                        message: String(
                            localized: "已保存 \(successes.count) 条运动轨迹，共 \(pointCount) 个轨迹点。"
                        )
                    )
                } else {
                    let summary = failures.prefix(3).joined(separator: "\n")
                    let remaining = max(failures.count - 3, 0)
                    let suffix = remaining > 0
                        ? String(localized: "\n另有 \(remaining) 个文件导入失败。")
                        : ""
                    trackImportNotice = TrackImportNotice(
                        title: successes.isEmpty
                            ? String(localized: "无法导入轨迹")
                            : String(localized: "部分轨迹已导入"),
                        message: summary + suffix
                    )
                }
            }
        }
    }

    private func focus(on track: ImportedTrack) {
        let points = track.segments.flatMap(\.points)
        guard
            let minimumLatitude = points.map(\.latitude).min(),
            let maximumLatitude = points.map(\.latitude).max(),
            let minimumLongitude = points.map(\.longitude).min(),
            let maximumLongitude = points.map(\.longitude).max()
        else { return }

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.25, 0.005),
                longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.25, 0.005)
            )
        )

        withAnimation {
            displayMode = .map
            showsImportedTracks = true
            is3DViewEnabled = false
            mapPosition = .region(region)
        }
    }

    private func deleteImportedTrack(_ track: ImportedTrack) {
        pendingTrackDeletion = nil
        Task {
            do {
                try await ImportedTrackStore.shared.delete(track)
                importedTracks.removeAll { $0.id == track.id }
            } catch {
                trackImportNotice = TrackImportNotice(
                    title: String(localized: "无法删除轨迹"),
                    message: String(localized: "请稍后再试。")
                )
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
        mapSearchRegion
    }

    private func selectSearchResult(_ result: PlaceSearchResult) {
        selectedSearchResult = result

        let region = MKCoordinateRegion(
            center: result.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        withAnimation {
            mapPosition = .region(region)
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
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white, lineWidth: 2.5)
            }
            .shadow(radius: 4, y: 1)
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
        let visited = point.culturalElementId.map { recordedElementIDs.contains($0) } ?? false
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

        if let elementID = point.culturalElementId,
           knowledgeStore?.element(id: elementID) != nil {
            NavigationLink(value: AppRoute.knowledgeElement(elementID)) {
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
                        if let elementID = point.culturalElementId,
                           knowledgeStore?.element(id: elementID) != nil {
                            NavigationLink(value: AppRoute.knowledgeElement(elementID)) {
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
        let visited = point.culturalElementId.map { recordedElementIDs.contains($0) } ?? false
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

            if point.culturalElementId != nil {
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
}

private extension UTType {
    static var gpx: UTType {
        UTType(filenameExtension: "gpx")
            ?? UTType(importedAs: "com.topografix.gpx", conformingTo: .data)
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
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        )
    }
}

#Preview {
    NavigationStack {
        CultureMapView(showsBackButton: false)
    }
    .modelContainer(for: ScanHistoryRecord.self, inMemory: true)
    .environment(AppLanguageStore())
}
