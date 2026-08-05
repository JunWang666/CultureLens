import MapKit
import SwiftUI

/// Compact location affordance for the capture-review overlay: icon → map popover.
struct ScanLocationPreviewButton: View {
    let place: PlaceContext?
    var isLoading: Bool = false

    @State private var showsMap = false

    private var hasPlace: Bool { place != nil }

    private var accessibilityText: Text {
        if isLoading {
            Text("正在获取位置")
        } else if let place {
            Text(place.displayName ?? String(localized: "查看扫描位置"))
        } else {
            Text("无可用位置")
        }
    }

    var body: some View {
        Button {
            guard hasPlace else { return }
            showsMap = true
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: hasPlace ? "location.fill" : "location.slash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(hasPlace ? CultureTheme.antiqueGold : .white.opacity(0.72))
                }
            }
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial.opacity(0.92), in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasPlace)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(hasPlace ? "显示地图" : "")
        .popover(
            isPresented: $showsMap,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            if let place {
                ScanLocationMapPopover(place: place)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
}

private struct ScanLocationMapPopover: View {
    let place: PlaceContext

    @State private var mapPosition: MapCameraPosition

    init(place: PlaceContext) {
        self.place = place
        let coordinate = CLLocationCoordinate2D(
            latitude: place.latitude,
            longitude: place.longitude
        )
        _mapPosition = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 900,
                    longitudinalMeters: 900
                )
            )
        )
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private var title: String {
        place.displayName ?? String(localized: "扫描位置")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Map(position: $mapPosition) {
                Marker(title, systemImage: "mappin.circle.fill", coordinate: coordinate)
                    .tint(CultureTheme.cinnabar)
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(width: 260, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text("位置地图：\(title)"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CultureTheme.inkPrimary)
                    .lineLimit(2)

                Text(coordinateCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(CultureTheme.inkSecondary)
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(width: 284)
    }

    private var coordinateCaption: String {
        let lat = place.latitude.formatted(.number.precision(.fractionLength(5)))
        let lon = place.longitude.formatted(.number.precision(.fractionLength(5)))
        if let accuracy = place.accuracyMeters, accuracy.isFinite, accuracy >= 0 {
            let meters = Int(accuracy.rounded())
            return "\(lat), \(lon) · ±\(meters) m"
        }
        return "\(lat), \(lon)"
    }
}
