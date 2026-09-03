import AppIntents
import Foundation
import WidgetKit

struct DocketItemEntity: AppEntity, Hashable, Sendable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Docket item")
    static let defaultQuery = DocketItemEntityQuery()

    let id: String
    let docketItemID: String
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
        // Include the local day in the App Entity identifier so Shortcuts cannot
        // silently rehydrate yesterday's cached entity as today's similarly named row.
        id = "\(day)::\(item.id)"
        docketItemID = item.id
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
        DocketItemEntityResolver.entities(matching: string, in: try currentSnapshot())
    }

    func suggestedEntities() async throws -> [DocketItemEntity] {
        try availableEntities()
    }

    private func availableEntities() throws -> [DocketItemEntity] {
        DocketItemEntityResolver.availableEntities(in: try currentSnapshot())
    }

    private func currentSnapshot() throws -> SharedDocketSnapshot? {
        try SharedDocketStore.live()?.currentEffectiveSnapshot()
    }
}

enum DocketItemEntityResolver {
    static func availableEntities(in snapshot: SharedDocketSnapshot?) -> [DocketItemEntity] {
        guard let snapshot else { return [] }
        return snapshot.items
            .filter { !$0.isCompleted && $0.supportsOneTapCompletion }
            .map { DocketItemEntity(item: $0, day: snapshot.day) }
    }

    /// Return every plausible match so Siri can disambiguate instead of silently
    /// choosing one row when two protocols use the same or similar name.
    static func entities(
        matching string: String,
        in snapshot: SharedDocketSnapshot?
    ) -> [DocketItemEntity] {
        let available = availableEntities(in: snapshot)
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return available }
        let exact = available.filter {
            $0.title.compare(query, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
                || ($0.tag?.compare(
                    query,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) == .orderedSame)
        }
        if !exact.isEmpty { return exact }
        return available.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.tag?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    static func item(
        for entity: DocketItemEntity,
        in snapshot: SharedDocketSnapshot?
    ) throws -> SharedDocketItem {
        guard let snapshot, snapshot.day == entity.day,
            let item = snapshot.items.first(where: { $0.id == entity.docketItemID }),
            item.supportsOneTapCompletion
        else { throw SharedDocketStoreError.itemUnavailable }
        return item
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
        let snapshot = try store.currentEffectiveSnapshot()
        let sharedItem = try DocketItemEntityResolver.item(for: item, in: snapshot)
        if sharedItem.isCompleted {
            return .result(dialog: "\(sharedItem.title) is already done.")
        }
        try store.enqueueCompletion(for: sharedItem, day: item.day)
        WidgetCenter.shared.reloadTimelines(ofKind: WhoopsWidgetConstants.kind)
        return .result(dialog: "Logged \(sharedItem.title) as prescribed.")
    }
}

enum WhoopsWidgetConstants {
    static let kind = "WhoopsDocketWidget"
}
