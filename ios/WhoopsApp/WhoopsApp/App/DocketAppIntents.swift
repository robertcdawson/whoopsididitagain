import AppIntents
import Foundation
import WidgetKit

struct DocketItemEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Docket item")
    static let defaultQuery = DocketItemEntityQuery()

    let id: String
    let day: String
    let title: String
    let tag: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: tag.map { "\($0) · today" } ?? "today"
        )
    }

    init(item: SharedDocketItem, day: String) {
        id = item.id
        self.day = day
        title = item.title
        tag = item.tag
    }
}

struct DocketItemEntityQuery: EntityStringQuery {
    func entities(for identifiers: [DocketItemEntity.ID]) async throws -> [DocketItemEntity] {
        try availableEntities().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [DocketItemEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try availableEntities() }
        return try availableEntities().filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.tag?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func suggestedEntities() async throws -> [DocketItemEntity] {
        try availableEntities()
    }

    private func availableEntities() throws -> [DocketItemEntity] {
        guard let store = SharedDocketStore.live(), let snapshot = try store.effectiveSnapshot()
        else { return [] }
        return snapshot.items
            .filter { !$0.isCompleted && $0.supportsOneTapCompletion }
            .map { DocketItemEntity(item: $0, day: snapshot.day) }
    }
}

struct CompleteDocketItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete docket item"
    static let description = IntentDescription(
        "Logs a protocol or wind-down item as prescribed without opening WHOOPs."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Docket item")
    var item: DocketItemEntity

    init() {}

    init(item: DocketItemEntity) {
        self.item = item
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let store = SharedDocketStore.live() else {
            throw SharedDocketStoreError.appGroupUnavailable
        }
        guard let snapshot = try store.effectiveSnapshot(), snapshot.day == item.day,
            let sharedItem = snapshot.items.first(where: { $0.id == item.id })
        else {
            throw SharedDocketStoreError.itemUnavailable
        }
        if sharedItem.isCompleted {
            return .result(dialog: "\(sharedItem.title) is already done.")
        }
        try store.enqueueCompletion(for: sharedItem, day: snapshot.day)
        WidgetCenter.shared.reloadTimelines(ofKind: WhoopsWidgetConstants.kind)
        return .result(dialog: "Logged \(sharedItem.title) as prescribed.")
    }
}

enum WhoopsWidgetConstants {
    static let kind = "WhoopsDocketWidget"
}
