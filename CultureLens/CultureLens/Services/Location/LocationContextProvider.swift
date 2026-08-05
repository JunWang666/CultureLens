@preconcurrency import CoreLocation
import Foundation
import MapKit
import Observation

enum LocationContextError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied:
            String(localized: "未获得位置权限，将只根据图片识别。")
        case .unavailable:
            String(localized: "暂时无法获取附近位置。")
        }
    }
}

@MainActor
@Observable
final class LocationContextProvider: NSObject {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PlaceContext, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestBestPlace() async throws -> PlaceContext {
        if let continuation {
            continuation.resume(throwing: CancellationError())
            self.continuation = nil
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                beginRequest()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(with: .failure(CancellationError()))
            }
        }
    }

    private func beginRequest() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(with: .failure(LocationContextError.denied))
        @unknown default:
            finish(with: .failure(LocationContextError.unavailable))
        }
    }

    private func resolve(_ location: CLLocation) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            var cityName: String?
            var regionName: String?
            var regionCode: String?
            var displayName: String?
            if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                if let request = MKReverseGeocodingRequest(location: location) {
                    request.preferredLocale = .current
                    if let mapItems = try? await request.mapItems {
                        let address = mapItems.first?.addressRepresentations
                        cityName = address?.cityName
                        regionName = address?.regionName
                        regionCode = address?.__regionCode
                        displayName = address?.cityWithContext(.full)
                    }
                }
            } else if let placemark = try? await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: .current
            ).first {
                cityName = placemark.locality
                regionName = placemark.country
                regionCode = placemark.isoCountryCode

                let displayComponents = [cityName, regionName]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                if !displayComponents.isEmpty {
                    displayName = displayComponents.joined(separator: "，")
                }
            }

            let place = PlaceContext(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracyMeters: location.horizontalAccuracy.isFinite
                    && location.horizontalAccuracy >= 0
                    ? location.horizontalAccuracy
                    : nil,
                cityName: cityName,
                regionName: regionName,
                regionCode: regionCode,
                displayName: displayName
            )
            finish(with: .success(place))
        }
    }

    private func finish(with result: Result<PlaceContext, Error>) {
        let pending = continuation
        continuation = nil
        pending?.resume(with: result)
    }
}

extension LocationContextProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self, continuation != nil else { return }
            beginRequest()
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else {
            locationManager(manager, didFailWithError: LocationContextError.unavailable)
            return
        }

        Task { @MainActor [weak self] in
            self?.resolve(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.finish(with: .failure(error))
        }
    }
}
