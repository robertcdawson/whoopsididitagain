import Foundation

/// The intentionally small cross-process representation used by the app, widget,
/// notification actions, and App Intents. The main SwiftData store remains owned
/// by the app; extensions receive only today's user-visible docket snapshot.
struct SharedDocketSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let generatedAt: Date
    let day: String
    var items: [SharedDocketItem]

    init(
        version: Int = Self.currentVersion,
        generatedAt: Date = .now,
        day: String,
        items: [SharedDocketItem]
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.day = day
        self.items = items
    }
}

struct SharedDocketItem: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let sourceID: String
    let protocolID: String?
    let title: String
    let tag: String?
    var isCompleted: Bool
    let prescribedSets: Int?
    let prescribedRepetitions: Int?
    let prescribedDurationSeconds: Int?

    var supportsOneTapCompletion: Bool {
        kind != "workout"
    }
}

struct SharedDocketCompletionAction: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let createdAt: Date
    let day: String
    let item: SharedDocketItem

    init(
        id: String = UUID().uuidString.lowercased(),
        createdAt: Date = .now,
        day: String,
        item: SharedDocketItem
    ) {
        self.id = id
        self.createdAt = createdAt
        self.day = day
        self.item = item
    }
}

enum SharedDocketStoreError: Error, Equatable, LocalizedError, Sendable {
    case appGroupUnavailable
    case unsupportedSnapshotVersion(Int)
    case itemUnavailable
    case workoutRequiresApp

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The shared docket container is unavailable."
        case .unsupportedSnapshotVersion(let version):
            "The shared docket uses unsupported version \(version)."
        case .itemUnavailable:
            "That docket item is no longer available today."
        case .workoutRequiresApp:
            "Open WHOOPs to record workout effort and pain."
        }
    }
}

/// File-per-action storage prevents two extension processes from overwriting one
/// another's queued work. Atomic snapshot writes plus an overlay of pending actions
/// keep the widget responsive while the app is suspended.
struct SharedDocketStore: Sendable {
    static let appGroupIdentifier = "group.com.robertcdawson.whoops"

    let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func live(fileManager: FileManager = .default) -> SharedDocketStore? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ).map(SharedDocketStore.init(rootURL:))
    }

    func snapshot() throws -> SharedDocketSnapshot? {
        let snapshotURL = rootURL.appendingPathComponent("docket-snapshot.json")
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        let snapshot = try decoder.decode(
            SharedDocketSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        guard snapshot.version == SharedDocketSnapshot.currentVersion else {
            throw SharedDocketStoreError.unsupportedSnapshotVersion(snapshot.version)
        }
        return snapshot
    }

    /// Returns the published app snapshot with pending outside-app completions
    /// overlaid. The action files are durable even if the app has not launched to
    /// reconcile them into SwiftData yet.
    func effectiveSnapshot() throws -> SharedDocketSnapshot? {
        guard var snapshot = try snapshot() else { return nil }
        let completedIDs = Set(
            try pendingCompletionActions()
                .filter { $0.day == snapshot.day }
                .map(\.item.id)
        )
        for index in snapshot.items.indices where completedIDs.contains(snapshot.items[index].id) {
            snapshot.items[index].isCompleted = true
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: SharedDocketSnapshot) throws {
        try prepareDirectories()
        let data = try encoder.encode(snapshot)
        try data.write(
            to: rootURL.appendingPathComponent("docket-snapshot.json"),
            options: .atomic
        )
    }

    @discardableResult
    func enqueueCompletion(
        for item: SharedDocketItem,
        day: String,
        at createdAt: Date = .now
    ) throws -> SharedDocketCompletionAction {
        guard item.supportsOneTapCompletion else {
            throw SharedDocketStoreError.workoutRequiresApp
        }
        try prepareDirectories()
        let action = SharedDocketCompletionAction(createdAt: createdAt, day: day, item: item)
        let data = try encoder.encode(action)
        try data.write(to: actionURL(id: action.id), options: .atomic)
        return action
    }

    func pendingCompletionActions() throws -> [SharedDocketCompletionAction] {
        let directory = actionsDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .map { try decoder.decode(SharedDocketCompletionAction.self, from: Data(contentsOf: $0)) }
        .sorted {
            ($0.createdAt, $0.id) < ($1.createdAt, $1.id)
        }
    }

    func acknowledgeCompletionAction(id: String) throws {
        let url = actionURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private var actionsDirectory: URL {
        rootURL.appendingPathComponent("docket-actions", isDirectory: true)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder { JSONDecoder() }

    private func actionURL(id: String) -> URL {
        actionsDirectory.appendingPathComponent("\(id).json")
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: actionsDirectory,
            withIntermediateDirectories: true
        )
    }
}
