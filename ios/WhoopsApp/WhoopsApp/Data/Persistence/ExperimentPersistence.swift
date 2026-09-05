import Foundation
import SwiftData

@Model
final class ExperimentRecord {
    @Attribute(.unique) var id: String
    var title: String
    var question: String
    var hypothesis: String
    var intervention: String
    var comparisonCondition: String
    var primaryOutcome: String
    var outcomeTiming: String?
    var secondaryOutcomesData: Data
    var inclusionCriteriaData: Data
    var exclusionCriteriaData: Data
    var minimumObservations: Int
    var potentialConfoundersData: Data
    var analysisMethod: String
    var startDate: Date
    var endDate: Date?
    var status: String
    var analysisVersion: String
    var createdAt: Date
    var updatedAt: Date

    init(
        experiment: ExperimentDefinition,
        secondaryOutcomesData: Data,
        inclusionCriteriaData: Data,
        exclusionCriteriaData: Data,
        potentialConfoundersData: Data
    ) {
        id = experiment.id
        title = experiment.title
        question = experiment.question
        hypothesis = experiment.hypothesis
        intervention = experiment.intervention
        comparisonCondition = experiment.comparisonCondition
        primaryOutcome = experiment.primaryOutcome.rawValue
        outcomeTiming = experiment.outcomeTiming.rawValue
        self.secondaryOutcomesData = secondaryOutcomesData
        self.inclusionCriteriaData = inclusionCriteriaData
        self.exclusionCriteriaData = exclusionCriteriaData
        minimumObservations = experiment.minimumObservations
        self.potentialConfoundersData = potentialConfoundersData
        analysisMethod = experiment.analysisMethod
        startDate = experiment.startDate
        endDate = experiment.endDate
        status = experiment.status.rawValue
        analysisVersion = experiment.analysisVersion
        createdAt = experiment.createdAt
        updatedAt = experiment.updatedAt
    }
}

@Model
final class ExperimentObservationRecord {
    @Attribute(.unique) var id: String
    var experimentID: String
    var day: String
    var condition: String
    var included: Bool
    var exclusionReason: String
    var confoundersData: Data
    var notes: String
    var updatedAt: Date

    init(observation: ExperimentObservation, confoundersData: Data) {
        id = observation.id
        experimentID = observation.experimentID
        day = observation.day
        condition = observation.condition.rawValue
        included = observation.included
        exclusionReason = observation.exclusionReason
        self.confoundersData = confoundersData
        notes = observation.notes
        updatedAt = observation.updatedAt
    }
}

@MainActor
final class ExperimentPersistence: ExperimentRepository, @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func experiments(includeArchived: Bool) async throws -> [ExperimentDefinition] {
        try context.fetch(FetchDescriptor<ExperimentRecord>())
            .compactMap(experiment)
            .filter { includeArchived || $0.status != .archived }
            .sorted { lhs, rhs in
                if lhs.status == rhs.status { return lhs.updatedAt > rhs.updatedAt }
                return lhs.status.sortOrder < rhs.status.sortOrder
            }
    }

    func saveExperiment(_ experiment: ExperimentDefinition) async throws {
        guard experiment.isValid else { throw ExperimentValidationError.invalidDefinition }
        let secondary = try encoder.encode(experiment.secondaryOutcomes)
        let inclusion = try encoder.encode(experiment.inclusionCriteria)
        let exclusion = try encoder.encode(experiment.exclusionCriteria)
        let confounders = try encoder.encode(experiment.potentialConfounders)
        let records = try context.fetch(FetchDescriptor<ExperimentRecord>())
        if let record = records.first(where: { $0.id == experiment.id }) {
            update(
                record,
                from: experiment,
                secondaryOutcomesData: secondary,
                inclusionCriteriaData: inclusion,
                exclusionCriteriaData: exclusion,
                potentialConfoundersData: confounders
            )
        } else {
            context.insert(
                ExperimentRecord(
                    experiment: experiment,
                    secondaryOutcomesData: secondary,
                    inclusionCriteriaData: inclusion,
                    exclusionCriteriaData: exclusion,
                    potentialConfoundersData: confounders
                )
            )
        }
        try context.save()
    }

    func deleteExperiment(id: String) async throws {
        try EditorDraftStore.shared.deleteSource(id)
        let experimentID = id
        for observation in try context.fetch(
            FetchDescriptor<ExperimentObservationRecord>(
                predicate: #Predicate { $0.experimentID == experimentID }
            )
        ) {
            context.delete(observation)
        }
        var experimentDescriptor = FetchDescriptor<ExperimentRecord>(
            predicate: #Predicate { $0.id == experimentID }
        )
        experimentDescriptor.fetchLimit = 1
        if let experiment = try context.fetch(experimentDescriptor).first {
            context.delete(experiment)
        }
        try context.save()
    }

    func observations(experimentID: String) async throws -> [ExperimentObservation] {
        try context.fetch(
            FetchDescriptor<ExperimentObservationRecord>(
                predicate: #Predicate { $0.experimentID == experimentID },
                sortBy: [SortDescriptor(\.day, order: .reverse)]
            )
        )
        .compactMap(observation)
    }

    func saveObservation(_ observation: ExperimentObservation) async throws {
        try await saveObservations([observation])
    }

    func replaceObservation(id originalID: String, with observation: ExperimentObservation)
        async throws
    {
        try validate(observation)
        let records = try context.fetch(FetchDescriptor<ExperimentObservationRecord>())
        if records.contains(where: {
            $0.id != originalID
                && $0.experimentID == observation.experimentID
                && $0.day == observation.day
        }) {
            throw ExperimentValidationError.observationDayConflict
        }

        let confounders = try encoder.encode(observation.confounders)
        if let original = records.first(where: { $0.id == originalID }) {
            update(original, from: observation, confoundersData: confounders)
        } else if let destination = records.first(where: {
            $0.experimentID == observation.experimentID && $0.day == observation.day
        }) {
            update(destination, from: observation, confoundersData: confounders)
        } else {
            context.insert(
                ExperimentObservationRecord(
                    observation: observation,
                    confoundersData: confounders
                )
            )
        }
        try context.save()
    }

    func saveObservations(_ observations: [ExperimentObservation]) async throws {
        try observations.forEach(validate)
        let records = try context.fetch(FetchDescriptor<ExperimentObservationRecord>())
        for observation in observations {
            let confounders = try encoder.encode(observation.confounders)
            if let record = records.first(where: {
                $0.id == observation.id
                    || ($0.experimentID == observation.experimentID && $0.day == observation.day)
            }) {
                update(record, from: observation, confoundersData: confounders)
            } else {
                context.insert(
                    ExperimentObservationRecord(
                        observation: observation,
                        confoundersData: confounders
                    )
                )
            }
        }
        try context.save()
    }

    private func validate(_ observation: ExperimentObservation) throws {
        guard
            observation.included
                || !observation.exclusionReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
        else { throw ExperimentValidationError.invalidObservation }
    }

    private func update(
        _ record: ExperimentObservationRecord,
        from observation: ExperimentObservation,
        confoundersData: Data
    ) {
        record.id = ExperimentObservation.stableID(
            experimentID: observation.experimentID,
            day: observation.day
        )
        record.experimentID = observation.experimentID
        record.day = observation.day
        record.condition = observation.condition.rawValue
        record.included = observation.included
        record.exclusionReason = observation.exclusionReason
        record.confoundersData = confoundersData
        record.notes = observation.notes
        record.updatedAt = observation.updatedAt
    }

    func deleteObservation(id: String) async throws {
        try EditorDraftStore.shared.deleteSource(id)
        let observationID = id
        var descriptor = FetchDescriptor<ExperimentObservationRecord>(
            predicate: #Predicate { $0.id == observationID }
        )
        descriptor.fetchLimit = 1
        if let observation = try context.fetch(descriptor).first {
            context.delete(observation)
        }
        try context.save()
    }

    private func experiment(_ record: ExperimentRecord) -> ExperimentDefinition? {
        guard let primary = ExperimentOutcome(rawValue: record.primaryOutcome),
            let status = ExperimentStatus(rawValue: record.status),
            let secondary = try? decoder.decode(
                [ExperimentOutcome].self,
                from: record.secondaryOutcomesData
            ),
            let inclusion = try? decoder.decode([String].self, from: record.inclusionCriteriaData),
            let exclusion = try? decoder.decode([String].self, from: record.exclusionCriteriaData),
            let confounders = try? decoder.decode(
                [String].self,
                from: record.potentialConfoundersData
            )
        else { return nil }
        return ExperimentDefinition(
            id: record.id,
            title: record.title,
            question: record.question,
            hypothesis: record.hypothesis,
            intervention: record.intervention,
            comparisonCondition: record.comparisonCondition,
            primaryOutcome: primary,
            outcomeTiming: ExperimentOutcomeTiming(rawValue: record.outcomeTiming ?? "")
                ?? primary.recommendedTiming,
            secondaryOutcomes: secondary,
            inclusionCriteria: inclusion,
            exclusionCriteria: exclusion,
            minimumObservations: record.minimumObservations,
            potentialConfounders: confounders,
            analysisMethod: record.analysisMethod,
            startDate: record.startDate,
            endDate: record.endDate,
            status: status,
            analysisVersion: record.analysisVersion,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private func observation(_ record: ExperimentObservationRecord) -> ExperimentObservation? {
        guard let condition = ExperimentCondition(rawValue: record.condition),
            let confounders = try? decoder.decode([String].self, from: record.confoundersData)
        else { return nil }
        return ExperimentObservation(
            id: record.id,
            experimentID: record.experimentID,
            day: record.day,
            condition: condition,
            included: record.included,
            exclusionReason: record.exclusionReason,
            confounders: confounders,
            notes: record.notes,
            updatedAt: record.updatedAt
        )
    }

    private func update(
        _ record: ExperimentRecord,
        from experiment: ExperimentDefinition,
        secondaryOutcomesData: Data,
        inclusionCriteriaData: Data,
        exclusionCriteriaData: Data,
        potentialConfoundersData: Data
    ) {
        record.title = experiment.title
        record.question = experiment.question
        record.hypothesis = experiment.hypothesis
        record.intervention = experiment.intervention
        record.comparisonCondition = experiment.comparisonCondition
        record.primaryOutcome = experiment.primaryOutcome.rawValue
        record.outcomeTiming = experiment.outcomeTiming.rawValue
        record.secondaryOutcomesData = secondaryOutcomesData
        record.inclusionCriteriaData = inclusionCriteriaData
        record.exclusionCriteriaData = exclusionCriteriaData
        record.minimumObservations = experiment.minimumObservations
        record.potentialConfoundersData = potentialConfoundersData
        record.analysisMethod = experiment.analysisMethod
        record.startDate = experiment.startDate
        record.endDate = experiment.endDate
        record.status = experiment.status.rawValue
        record.analysisVersion = experiment.analysisVersion
        record.createdAt = experiment.createdAt
        record.updatedAt = experiment.updatedAt
    }
}

extension ExperimentStatus {
    fileprivate var sortOrder: Int {
        switch self {
        case .active: 0
        case .draft: 1
        case .completed: 2
        case .archived: 3
        }
    }
}
