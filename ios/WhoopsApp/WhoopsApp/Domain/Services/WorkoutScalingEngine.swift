import Foundation

struct DeterministicWorkoutScalingEngine: WorkoutScalingEngine {
    static let rulesetVersion = "workout-scaling-1.0.1"
    let catalog: MovementCatalog

    init(catalog: MovementCatalog = .standard) {
        self.catalog = catalog
    }

    func evaluate(
        plan: WorkoutPlan,
        restrictions: [RestrictionProfile]
    ) async -> WorkoutEvaluation {
        var conflicts: [WorkoutConflict] = []
        for movement in plan.movements {
            guard let movementID = movement.canonicalMovementID,
                let item = catalog.item(id: movementID)
            else {
                for restriction in restrictions where restriction.isActive {
                    conflicts.append(
                        WorkoutConflict(
                            id: "\(movement.id):\(restriction.id):unmapped",
                            movementID: movement.id,
                            restrictionID: restriction.id,
                            severity: .caution,
                            explanation:
                                "\(movement.displayName) is not mapped to a reviewed movement, so it cannot be evaluated against the \(restriction.injuryName) restriction.",
                            preservedStimulus:
                                "Map or manually review this movement before relying on an automatic recommendation.",
                            compromise: "The workout evaluation is incomplete for this movement.",
                            substitutionCandidates: []
                        )
                    )
                }
                continue
            }
            for restriction in restrictions where restriction.isActive {
                if item.tags.isEmpty {
                    conflicts.append(
                        WorkoutConflict(
                            id: "\(movement.id):\(restriction.id):untagged",
                            movementID: movement.id,
                            restrictionID: restriction.id,
                            severity: .caution,
                            explanation:
                                "\(item.canonicalName) has not been reviewed for movement demands, so it cannot be confirmed against the \(restriction.injuryName) restriction.",
                            preservedStimulus:
                                "Review this movement’s restriction demand tags before relying on an automatic recommendation.",
                            compromise:
                                "The movement remains available for planning, but requires manual safety review.",
                            substitutionCandidates: []
                        )
                    )
                    continue
                }
                let restrictedDemands = Self.demands(for: restriction.movementTag)
                let matchedDemands = item.tags.intersection(restrictedDemands)
                guard !matchedDemands.isEmpty else { continue }
                let candidates = item.substitutionCandidates
                    .compactMap(catalog.item)
                    .filter { $0.tags.isDisjoint(with: restrictedDemands) }
                let demands = matchedDemands.map(\.displayName).sorted().joined(separator: ", ")
                conflicts.append(
                    WorkoutConflict(
                        id: "\(movement.id):\(restriction.id)",
                        movementID: movement.id,
                        restrictionID: restriction.id,
                        severity: restriction.level.isHard ? .hard : .caution,
                        explanation:
                            "\(item.canonicalName) includes \(demands.lowercased()), which conflicts with the \(restriction.injuryName) restriction.",
                        preservedStimulus:
                            "Candidates prioritize \(plan.intendedStimulus.primary.lowercased()) without the restricted demand.",
                        compromise:
                            "A substitution may reduce movement specificity while retaining the session’s broader intent.",
                        substitutionCandidates: candidates
                    )
                )
            }
        }

        let recommendation: ReadinessAssessment.Recommendation
        if conflicts.contains(where: { $0.severity == .hard }) {
            recommendation = .modify
        } else if conflicts.isEmpty {
            recommendation = .proceed
        } else {
            recommendation = .proceedWithLimits
        }
        return WorkoutEvaluation(
            recommendation: recommendation,
            conflicts: conflicts,
            reasonCodes: conflicts.map {
                "workout.conflict.\($0.severity.rawValue).\($0.restrictionID)"
            }
        )
    }

    private static func demands(for text: String) -> Set<MovementDemand> {
        if let demand = MovementDemand(rawValue: text) { return [demand] }
        let normalized = text.lowercased().replacingOccurrences(of: "-", with: " ")
        var demands: Set<MovementDemand> = []
        if normalized.contains("elbow extension") { demands.insert(.elbowExtension) }
        if normalized.contains("ballistic") && normalized.contains("elbow") {
            demands.insert(.ballisticElbowExtension)
        }
        if normalized.contains("overhead") { demands.insert(.overhead) }
        if normalized.contains("vertical pull") { demands.insert(.verticalPull) }
        if normalized.contains("grip") { demands.insert(.gripIntensive) }
        if normalized.contains("spinal flexion") { demands.insert(.spinalFlexionRisk) }
        if normalized.contains("compression") { demands.insert(.spinalCompression) }
        if normalized.contains("knee") { demands.insert(.kneeDominant) }
        if normalized.contains("high impact") { demands.insert(.highImpact) }
        if normalized.contains("foot") || normalized.contains("running") {
            demands.insert(.footImpact)
        }
        return demands
    }
}
