import Foundation
import Observation

@MainActor
@Observable
final class KnowledgeProgressStore {
    nonisolated static let defaultStorageKey = "culturelens.understood-node-ids.v1"

    private(set) var understoodNodeIDs: Set<UUID>

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = KnowledgeProgressStore.defaultStorageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        understoodNodeIDs = Set(
            (userDefaults.stringArray(forKey: storageKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    func isUnderstood(_ nodeID: UUID) -> Bool {
        understoodNodeIDs.contains(nodeID)
    }

    func toggleUnderstanding(_ nodeID: UUID) {
        if understoodNodeIDs.contains(nodeID) {
            understoodNodeIDs.remove(nodeID)
        } else {
            understoodNodeIDs.insert(nodeID)
        }
        persist()
    }

    private func persist() {
        userDefaults.set(
            understoodNodeIDs
                .map(\.uuidString)
                .sorted(),
            forKey: storageKey
        )
    }
}
