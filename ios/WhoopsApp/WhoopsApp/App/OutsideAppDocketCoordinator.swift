import Foundation
import WidgetKit

/// Reconciles durable extension actions into the app-owned completion repository.
/// An action is acknowledged only after the authoritative docket has been rebuilt
/// and published, so an interrupted launch safely retries an idempotent upsert.
actor OutsideAppDocketCoordinator {
    private let repository: any DocketRepository
    private let store: SharedDocketStore?

    init(
        repository: any DocketRepository,
        store: SharedDocketStore? = SharedDocketStore.live()
    ) {
        self.repository = repository
        self.store = store
    }

    func reconcilePendingCompletions() async throws -> [String] {
        guard let store else { return [] }
        let actions = try store.pendingCompletionActions()
        for action in actions {
            guard let item = DocketItem(shared: action.item) else { continue }
            try await repository.saveCompletion(
                .asPrescribed(item: item, day: action.day, at: action.createdAt)
            )
        }
        return actions.map(\.id)
    }

    func publish(_ docket: DailyDocket, acknowledging actionIDs: [String] = []) throws {
        guard let store else { return }
        try store.saveSnapshot(
            SharedDocketSnapshot(
                day: docket.day,
                items: docket.items.map(SharedDocketItem.init(item:))
            )
        )
        for id in actionIDs {
            try store.acknowledgeCompletionAction(id: id)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WhoopsWidgetConstants.kind)
    }
}

extension SharedDocketItem {
    init(item: DocketItem) {
        self.init(
            id: item.id,
            kind: item.kind.rawValue,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            title: item.title,
            tag: item.tag,
            isCompleted: item.isCompleted,
            prescribedSets: item.prescribedSets,
            prescribedRepetitions: item.prescribedRepetitions,
            prescribedDurationSeconds: item.prescribedDurationSeconds
        )
    }
}

extension DocketItem {
    init?(shared item: SharedDocketItem) {
        guard let kind = DocketItemKind(rawValue: item.kind), kind != .workout else { return nil }
        self.init(
            id: item.id,
            kind: kind,
            sourceID: item.sourceID,
            protocolID: item.protocolID,
            title: item.title,
            tag: item.tag,
            isCompleted: item.isCompleted,
            completionID: nil,
            prescribedSets: item.prescribedSets,
            prescribedRepetitions: item.prescribedRepetitions,
            prescribedDurationSeconds: item.prescribedDurationSeconds,
            recordedActual: nil
        )
    }
}
