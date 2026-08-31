import Foundation

struct LibraryWorkoutParser: WorkoutParser {
    let library: any MovementLibraryRepository
    var model: (any WorkoutTextGenerating)? = nil
    var isAIEnabled: @Sendable () -> Bool = { true }
    var timeout: Duration = .seconds(20)

    func parse(rawText: String) async throws -> ParsedWorkout {
        try await library.prepareDefaults()
        let movements = try await library.movements(includeArchived: false)
        let catalog = MovementCatalog(items: movements.map(\.catalogItem))
        let fallback = VersionedWorkoutParser(catalog: catalog)
        try Task.checkCancellation()
        guard let model, isAIEnabled() else { return try await fallback.parse(rawText: rawText) }
        do {
            let parsed = try await OnDeviceWorkoutParser(
                model: model, catalog: catalog, timeout: timeout
            )
            .parse(rawText: rawText)
            guard
                !parsed.ambiguities.contains(where: { $0.id.hasPrefix("apple-parser-incomplete-") })
            else { throw WorkoutAIFailure.invalidOutput }
            return parsed
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            var parsed = try await fallback.parse(rawText: rawText)
            let reason = (error as? WorkoutAIFailure) ?? .generationFailed
            parsed.ambiguities.insert(
                .init(
                    id: "apple-parser-fallback", line: nil, originalText: "Built-in parser used",
                    message:
                        "\(reason.message) Your text stayed on this device. Review the fallback draft."
                ), at: 0)
            return parsed
        }
    }
}

struct LibraryProtocolParser: ProtocolParser {
    let library: any MovementLibraryRepository

    func parse(rawText: String, source: ProtocolSource) async throws -> ParsedProtocol {
        try await library.prepareDefaults()
        let movements = try await library.movements(includeArchived: false)
        return try await DeterministicProtocolParser(
            catalog: MovementCatalog(items: movements.map(\.catalogItem))
        ).parse(rawText: rawText, source: source)
    }
}

struct LibraryWorkoutScalingEngine: WorkoutScalingEngine {
    let library: any MovementLibraryRepository

    func evaluate(
        plan: WorkoutPlan,
        restrictions: [RestrictionProfile]
    ) async -> WorkoutEvaluation {
        do {
            try await library.prepareDefaults()
            let movements = try await library.movements(includeArchived: true)
            return await DeterministicWorkoutScalingEngine(
                catalog: MovementCatalog(items: movements.map(\.catalogItem))
            ).evaluate(plan: plan, restrictions: restrictions)
        } catch {
            return await DeterministicWorkoutScalingEngine().evaluate(
                plan: plan,
                restrictions: restrictions
            )
        }
    }
}
