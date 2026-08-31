import Foundation

enum FeatureFlags {
    static let experimentLabKey = "feature.experimentLab"

    /// The Apple parser has not passed its live quality gate. Only simulator UI tests can
    /// exercise the prototype's controls, using a synthetic provider rather than the live model.
    /// A previously stored opt-in cannot enable it in an ordinary run or on a physical device.
    static func appleWorkoutParserTestModeEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG && targetEnvironment(simulator)
            ["fixture", "slow", "unavailable"].contains(
                environment["WHOOPS_TEST_WORKOUT_MODEL"] ?? "")
        #else
            false
        #endif
    }

    static func experimentLabEnabled(
        storedValue: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        storedValue || environment["WHOOPS_ENABLE_EXPERIMENT_LAB"] == "1"
    }
}
