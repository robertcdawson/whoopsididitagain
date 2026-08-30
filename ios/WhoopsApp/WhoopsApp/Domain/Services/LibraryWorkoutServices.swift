import Foundation

struct LibraryWorkoutParser: WorkoutParser {
    let library: any MovementLibraryRepository

    func parse(rawText: String) async throws -> ParsedWorkout {
        try await library.prepareDefaults()
        let movements = try await library.movements(includeArchived: false)
        return try await VersionedWorkoutParser(
            catalog: MovementCatalog(items: movements.map(\.catalogItem))
        ).parse(rawText: rawText)
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
