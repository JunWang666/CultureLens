import MapKit
import SwiftUI

/// Full-screen MapKit sheet for picking an introduction coordinate.
struct PackLocationPickerView: View {
  let initialLatitudeText: String
  let initialLongitudeText: String
  let onConfirm: (_ latitude: String, _ longitude: String, _ appleMapsURL: String) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var mapPosition: MapCameraPosition
  @State private var selectedCoordinate: CLLocationCoordinate2D
  @State private var searchText = ""
  @State private var searchResults: [SearchResult] = []
  @State private var isSearching = false
  @State private var searchErrorMessage: String?
  @State private var isLocatingUser = false
  @State private var locationAlertMessage: String?
  @State private var locationProvider = LocationContextProvider()
  @FocusState private var isSearchFocused: Bool

  private struct SearchResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
  }

  init(
    initialLatitudeText: String,
    initialLongitudeText: String,
    onConfirm: @escaping (_ latitude: String, _ longitude: String, _ appleMapsURL: String) -> Void
  ) {
    self.initialLatitudeText = initialLatitudeText
    self.initialLongitudeText = initialLongitudeText
    self.onConfirm = onConfirm

    let coordinate = PackCoordinateFormatting.initialCoordinate(
      latitudeText: initialLatitudeText,
      longitudeText: initialLongitudeText
    )
    _selectedCoordinate = State(initialValue: coordinate)
    _mapPosition = State(
      initialValue: .region(
        MKCoordinateRegion(
          center: coordinate,
          latitudinalMeters: 700,
          longitudinalMeters: 700
        )
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        mapLayer

        VStack(spacing: 0) {
          searchPanel
            .padding(.horizontal, 12)
            .padding(.top, 8)

          Spacer(minLength: 0)

          readoutBar
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
      }
      .navigationTitle("选择位置")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("使用此位置") { confirmSelection() }
            .fontWeight(.semibold)
            .accessibilityIdentifier("packEditor.locationPicker.confirm")
        }
        ToolbarItem(placement: .topBarTrailing) {
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
          .accessibilityLabel("定位到我的位置")
        }
      }
      .alert("无法定位", isPresented: Binding(
        get: { locationAlertMessage != nil },
        set: { if !$0 { locationAlertMessage = nil } }
      )) {
        Button("好", role: .cancel) { locationAlertMessage = nil }
      } message: {
        Text(locationAlertMessage ?? "")
      }
      .task {
        await applyUserLocationIfDraftUnset()
      }
      .task(id: searchText) {
        await searchPlaces()
      }
    }
  }

  private var mapLayer: some View {
    Map(position: $mapPosition) {
      UserAnnotation()
    }
    .mapStyle(.standard(elevation: .realistic))
    .mapControls {
      MapCompass()
      MapScaleView()
    }
    .onMapCameraChange(frequency: .continuous) { context in
      selectedCoordinate = context.camera.centerCoordinate
    }
    .overlay {
      Image(systemName: "mappin")
        .font(.system(size: 36, weight: .semibold))
        .foregroundStyle(CultureTheme.cinnabar)
        .offset(y: -18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    .ignoresSafeArea(edges: .bottom)
    .accessibilityLabel("地图选点，拖动地图使中心对准目标位置")
  }

  private var searchPanel: some View {
    VStack(alignment: .leading, spacing: 8) {
      searchField
      if isSearchFocused, !trimmedSearchText.isEmpty {
        searchResultsSurface
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("搜索地点或地址", text: $searchText)
        .textFieldStyle(.plain)
        .focused($isSearchFocused)
        .submitLabel(.search)
        .accessibilityIdentifier("packEditor.locationPicker.search")
      if !searchText.isEmpty {
        Button {
          searchText = ""
          searchResults = []
          searchErrorMessage = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("清除搜索")
      }
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(.ultraThinMaterial, in: Capsule())
  }

  private var searchResultsSurface: some View {
    Group {
      if isSearching {
        Label("正在搜索…", systemImage: "magnifyingglass")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      } else if let searchErrorMessage {
        Label(searchErrorMessage, systemImage: "exclamationmark.triangle")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      } else if searchResults.isEmpty {
        Label("未找到地点", systemImage: "mappin.slash")
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .frame(maxHeight: 240)
      }
    }
    .background(
      .ultraThinMaterial,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
  }

  private var readoutBar: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("拖动地图，使中心钉对准目标位置")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(coordinateCaption)
        .font(.subheadline.monospacedDigit().weight(.semibold))
        .foregroundStyle(CultureTheme.inkPrimary)
        .accessibilityIdentifier("packEditor.locationPicker.coordinate")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private var coordinateCaption: String {
    let lat = PackCoordinateFormatting.format(selectedCoordinate.latitude)
    let lon = PackCoordinateFormatting.format(selectedCoordinate.longitude)
    return "\(lat), \(lon)"
  }

  private var trimmedSearchText: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func confirmSelection() {
    let latitude = PackCoordinateFormatting.format(selectedCoordinate.latitude)
    let longitude = PackCoordinateFormatting.format(selectedCoordinate.longitude)
    let url = PackCoordinateFormatting.appleMapsURL(
      latitude: selectedCoordinate.latitude,
      longitude: selectedCoordinate.longitude
    )
    onConfirm(latitude, longitude, url)
    dismiss()
  }

  private func selectSearchResult(_ result: SearchResult) {
    selectedCoordinate = result.coordinate
    withAnimation {
      mapPosition = .region(
        MKCoordinateRegion(
          center: result.coordinate,
          latitudinalMeters: 600,
          longitudinalMeters: 600
        )
      )
    }
    searchText = ""
    searchResults = []
    searchErrorMessage = nil
    isSearchFocused = false
  }

  private var draftHasUsableCoordinate: Bool {
    guard let coordinate = PackCoordinateFormatting.coordinate(
      latitudeText: initialLatitudeText,
      longitudeText: initialLongitudeText
    ) else { return false }
    return !PackCoordinateFormatting.isUnsetOrigin(
      latitude: coordinate.latitude,
      longitude: coordinate.longitude
    )
  }

  private func applyUserLocationIfDraftUnset() async {
    guard !draftHasUsableCoordinate else { return }
    await centerOnUserLocation(animated: false, showsErrorAlert: false)
  }

  private func locateUser() {
    guard !isLocatingUser else { return }
    isLocatingUser = true
    Task {
      defer { isLocatingUser = false }
      await centerOnUserLocation(animated: true, showsErrorAlert: true)
    }
  }

  private func centerOnUserLocation(animated: Bool, showsErrorAlert: Bool) async {
    do {
      let place = try await locationProvider.requestBestPlace()
      let coordinate = CLLocationCoordinate2D(
        latitude: place.latitude,
        longitude: place.longitude
      )
      selectedCoordinate = coordinate
      let region = MKCoordinateRegion(
        center: coordinate,
        latitudinalMeters: 700,
        longitudinalMeters: 700
      )
      if animated {
        withAnimation { mapPosition = .region(region) }
      } else {
        mapPosition = .region(region)
      }
    } catch {
      if showsErrorAlert {
        locationAlertMessage = error.localizedDescription
      }
    }
  }

  private func searchPlaces() async {
    let query = trimmedSearchText
    guard !query.isEmpty else {
      searchResults = []
      searchErrorMessage = nil
      isSearching = false
      return
    }

    isSearching = true
    searchErrorMessage = nil

    do {
      try await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }

      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.resultTypes = [.address, .pointOfInterest]
      request.region = MKCoordinateRegion(
        center: selectedCoordinate,
        latitudinalMeters: 40_000,
        longitudinalMeters: 40_000
      )

      let response = try await MKLocalSearch(request: request).start()
      guard !Task.isCancelled,
            searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
      else { return }

      searchResults = response.mapItems.prefix(8).compactMap { item in
        let coordinate = item.placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
        let name = item.name ?? String(localized: "未命名地点")
        let title = item.placemark.title
        let subtitle = (title != nil && title != name) ? title : nil
        return SearchResult(name: name, subtitle: subtitle, coordinate: coordinate)
      }
      isSearching = false
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled else { return }
      searchResults = []
      searchErrorMessage = String(localized: "搜索暂时不可用")
      isSearching = false
    }
  }
}

#if DEBUG
#Preview {
  PackLocationPickerView(
    initialLatitudeText: "30.2425",
    initialLongitudeText: "120.1483"
  ) { _, _, _ in }
}
#endif
