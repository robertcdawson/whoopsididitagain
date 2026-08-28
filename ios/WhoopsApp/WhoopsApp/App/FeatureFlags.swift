import Foundation

enum FeatureFlags {
    static let experimentLabKey = "feature.experimentLab"

    static func experimentLabEnabled(
        storedValue: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        storedValue || environment["WHOOPS_ENABLE_EXPERIMENT_LAB"] == "1"
    }
}
