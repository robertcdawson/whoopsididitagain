import Foundation

struct DeterministicExperimentEngine: Sendable {
    static let version = "experiments-1.1.0"

    func analyze(
        experiment: ExperimentDefinition,
        observations: [ExperimentObservation],
        input: ExperimentAnalysisInput,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ExperimentAnalysis {
        let resolved =
            observations
            .filter { $0.experimentID == experiment.id }
            .sorted { $0.day > $1.day }
            .map {
                let outcomeDay = outcomeDay(
                    for: $0.day,
                    timing: experiment.outcomeTiming,
                    calendar: calendar
                )
                return ExperimentResolvedObservation(
                    observation: $0,
                    outcomeDay: outcomeDay,
                    outcomeValue: resolve(
                        experiment.primaryOutcome,
                        day: outcomeDay,
                        input: input,
                        calendar: calendar
                    )
                )
            }
        let included = resolved.filter { $0.observation.included && $0.outcomeValue != nil }
        let interventionValues = included.compactMap {
            $0.observation.condition == .intervention ? $0.outcomeValue : nil
        }
        let comparisonValues = included.compactMap {
            $0.observation.condition == .comparison ? $0.outcomeValue : nil
        }
        let interventionMean = mean(interventionValues)
        let comparisonMean = mean(comparisonValues)
        let thresholdMet =
            interventionValues.count >= experiment.minimumObservations
            && comparisonValues.count >= experiment.minimumObservations
        let difference =
            thresholdMet
            ? interventionMean.flatMap { intervention in
                comparisonMean.map { intervention - $0 }
            } : nil
        let evidenceStatus: ExperimentEvidenceStatus
        if !thresholdMet {
            evidenceStatus = .insufficientData
        } else if max(interventionValues.count, comparisonValues.count)
            >= 2 * max(1, min(interventionValues.count, comparisonValues.count))
        {
            evidenceStatus = .imbalanced
        } else {
            evidenceStatus = .exploratory
        }
        let missingCount = resolved.filter { $0.observation.included && $0.outcomeValue == nil }
            .count
        let summary: String
        if let difference {
            summary =
                "\(experiment.intervention): mean \(format(interventionMean)) \(experiment.primaryOutcome.unit) across \(interventionValues.count) days. \(experiment.comparisonCondition): mean \(format(comparisonMean)) \(experiment.primaryOutcome.unit) across \(comparisonValues.count) days. The observed association was \(signed(difference)) \(experiment.primaryOutcome.unit) (first condition minus second condition)."
        } else {
            summary =
                "Not enough usable days yet. \(experiment.intervention): \(interventionValues.count) of \(experiment.minimumObservations). \(experiment.comparisonCondition): \(comparisonValues.count) of \(experiment.minimumObservations). A difference appears only after both conditions reach the minimum."
        }
        let missingText =
            missingCount == 0
            ? ""
            : " \(missingCount) included observations currently have no matching outcome value."
        return ExperimentAnalysis(
            version: Self.version,
            outcome: experiment.primaryOutcome,
            observations: resolved,
            interventionCount: interventionValues.count,
            comparisonCount: comparisonValues.count,
            missingOutcomeCount: missingCount,
            interventionMean: interventionMean,
            comparisonMean: comparisonMean,
            observedDifference: difference,
            evidenceStatus: evidenceStatus,
            summary: summary,
            caveat:
                "This is a descriptive personal association, not evidence of causation, treatment efficacy, diagnosis, or medical advice. Confounding and condition imbalance may explain the difference.\(missingText)"
        )
    }

    func outcomeDay(
        for conditionDay: String,
        timing: ExperimentOutcomeTiming,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        guard timing == .followingDay,
            let date = date(from: conditionDay, calendar: calendar),
            let followingDate = calendar.date(byAdding: .day, value: 1, to: date)
        else { return conditionDay }
        return dayKey(followingDate, calendar: calendar)
    }

    func resolve(
        _ outcome: ExperimentOutcome,
        day: String,
        input: ExperimentAnalysisInput,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double? {
        switch outcome {
        case .sleepDuration:
            return input.trends.sleep.points.last { dayKey($0.date, calendar: calendar) == day }?
                .value
        case .trainingLoad:
            return input.trends.dailyTrainingLoads.first { $0.day == day }?.load
        case .morningPainWithMovement:
            return input.checkIns.first { $0.day == day }.map { Double($0.painWithMovement) }
        default:
            guard let metricID = outcome.trendMetricID,
                let metric = input.trends.recoveryMetrics.first(where: { $0.id == metricID })
            else { return nil }
            return metric.points.last { dayKey($0.date, calendar: calendar) == day }?.value
        }
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func date(from day: String, calendar: Calendar) -> Date? {
        let values = day.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        return calendar.date(
            from: DateComponents(year: values[0], month: values[1], day: values[2])
        )
    }

    private func format(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(1))) ?? "—"
    }

    private func signed(_ value: Double) -> String {
        "\(value >= 0 ? "+" : "")\(value.formatted(.number.precision(.fractionLength(1))))"
    }
}
