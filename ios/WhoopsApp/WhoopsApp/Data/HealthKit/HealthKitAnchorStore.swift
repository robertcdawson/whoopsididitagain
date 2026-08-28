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

final class HealthMetricInclusionStore: HealthMetricInclusionStoring, @unchecked Sendable {
    private enum Key {
        static let excludedMetrics = "healthkit.excluded-metrics.v1"
    }

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func includedMetrics() -> Set<HealthMetric> {
        lock.withLock {
            let excluded = Set(
                (defaults.stringArray(forKey: Key.excludedMetrics) ?? []).compactMap(
                    HealthMetric.init(rawValue:)
                )
            )
            return Set(HealthMetric.allCases).subtracting(excluded)
        }
    }

    func setMetric(_ metric: HealthMetric, included: Bool) {
        lock.withLock {
            var excluded = Set(defaults.stringArray(forKey: Key.excludedMetrics) ?? [])
            if included {
                excluded.remove(metric.rawValue)
            } else {
                excluded.insert(metric.rawValue)
            }
            defaults.set(excluded.sorted(), forKey: Key.excludedMetrics)
        }
    }
}
