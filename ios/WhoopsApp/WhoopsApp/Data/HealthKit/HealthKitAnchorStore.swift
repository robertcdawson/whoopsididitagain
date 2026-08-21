import Foundation

final class HealthKitAnchorStore: HealthKitAnchorStoring, @unchecked Sendable {
    private enum Key {
        static let authorizationRequested = "healthkit.authorization-requested.v1"
        static let anchorPrefix = "healthkit.anchor.v1."
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func authorizationWasRequested() -> Bool {
        lock.withLock { defaults.bool(forKey: Key.authorizationRequested) }
    }

    func markAuthorizationRequested() {
        lock.withLock { defaults.set(true, forKey: Key.authorizationRequested) }
    }

    func anchorData(for metric: HealthMetric) -> Data? {
        lock.withLock { defaults.data(forKey: Key.anchorPrefix + metric.rawValue) }
    }

    func saveAnchorData(_ data: Data, for metric: HealthMetric) {
        lock.withLock { defaults.set(data, forKey: Key.anchorPrefix + metric.rawValue) }
    }
}
