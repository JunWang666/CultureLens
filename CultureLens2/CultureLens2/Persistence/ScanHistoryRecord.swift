import Foundation
import SwiftData

@Model
final class ScanHistoryRecord {
    @Attribute(.unique) var recordID: UUID
    var createdAt: Date
    var cultureObjectID: UUID
    var canonicalName: String
    var categoryRawValue: String
    var summary: String
    var timePeriod: String?
    var region: String?
    var confidence: Double
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var imageRelativePath: String?
    var modelIdentifier: String
    var resultSnapshotData: Data
    var isBookmarked: Bool

    init(
        recordID: UUID,
        createdAt: Date,
        cultureObjectID: UUID,
        canonicalName: String,
        categoryRawValue: String,
        summary: String,
        timePeriod: String?,
        region: String?,
        confidence: Double,
        latitude: Double?,
        longitude: Double?,
        placeName: String?,
        imageRelativePath: String?,
        modelIdentifier: String,
        resultSnapshotData: Data,
        isBookmarked: Bool = false
    ) {
        self.recordID = recordID
        self.createdAt = createdAt
        self.cultureObjectID = cultureObjectID
        self.canonicalName = canonicalName
        self.categoryRawValue = categoryRawValue
        self.summary = summary
        self.timePeriod = timePeriod
        self.region = region
        self.confidence = confidence
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.imageRelativePath = imageRelativePath
        self.modelIdentifier = modelIdentifier
        self.resultSnapshotData = resultSnapshotData
        self.isBookmarked = isBookmarked
    }

    var place: PlaceContext? {
        guard let latitude, let longitude else { return nil }
        return PlaceContext(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: nil,
            cityName: nil,
            regionName: nil,
            regionCode: nil,
            displayName: placeName
        )
    }
}
