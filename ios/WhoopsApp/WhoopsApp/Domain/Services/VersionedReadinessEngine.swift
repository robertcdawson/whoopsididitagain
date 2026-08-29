import Foundation

struct VersionedReadinessEngine: ReadinessEngine {
    static let rulesetVersion = "readiness-1.0.1"
    private static let hardRestrictionTissueScoreCeiling = 39

    func assess(_ input: ReadinessInput) async throws -> ReadinessAssessment {
        var reasons: [ReadinessReason] = []
        let hrvBaseline = RobustBaseline.calculate(input.physiology.whoopHRVHistory)
        let sdnnBaseline = RobustBaseline.calculate(input.physiology.appleHRVHistory)
        let heartRateBaseline = RobustBaseline.calculate(
            input.physiology.restingHeartRateHistory
        )
        let sleepScore = input.physiology.sleepMinutes.map {
            min(
                100,
                max(
                    0,
                    Int(
                        (Double($0) / Double(input.sleepSettings.targetSleepMinutes) * 100)
                            .rounded())))
        }
        let tissueScore = Self.tissueScore(
            input.checkIn,
            restrictions: input.activeRestrictions
        )
        var systemicScore = Self.initialSystemicScore(input)

        if let recovery = input.physiology.whoopRecovery {
            reasons.append(
                ReadinessReason(
                    code: "whoop.recovery",
                    message: "WHOOP Recovery is \(recovery)%.",
                    direction: recovery >= 67 ? .positive : .caution,
                    priority: recovery < 34 ? 90 : 40
                )
            )
        } else {
            reasons.append(Self.missing("whoop.recovery.missing", "WHOOP Recovery is unavailable."))
        }

        Self.applyHRVSignal(
            name: "WHOOP HRV RMSSD",
            code: "whoop.hrv-rmssd",
            current: input.physiology.whoopHRVRMSSD,
            baseline: hrvBaseline,
            systemicScore: &systemicScore,
            reasons: &reasons
        )
        Self.applyHRVSignal(
            name: "Apple Health HRV SDNN",
            code: "apple.hrv-sdnn",
            current: input.physiology.appleHRVSDNN,
            baseline: sdnnBaseline,
            systemicScore: &systemicScore,
            reasons: &reasons
        )
        Self.applyRestingHeartRateSignal(
            current: input.physiology.restingHeartRate,
            baseline: heartRateBaseline,
            systemicScore: &systemicScore,
            reasons: &reasons
        )

        if let sleepMinutes = input.physiology.sleepMinutes, let sleepScore {
            let difference = sleepMinutes - input.sleepSettings.targetSleepMinutes
            let description =
                difference >= 0
                ? "Sleep met the target by \(difference) minutes."
                : "Sleep was \(-difference) minutes below the target."
            reasons.append(
                ReadinessReason(
                    code: "sleep.sufficiency",
                    message: description,
                    direction: sleepScore >= 90 ? .positive : .caution,
                    priority: sleepScore < 70 ? 80 : 35
                )
            )
        } else {
            reasons.append(Self.missing("sleep.missing", "Sleep duration is unavailable."))
        }

        if let checkIn = input.checkIn {
            if checkIn.illnessSymptoms {
                systemicScore = systemicScore.map { max(0, $0 - 25) } ?? 35
                reasons.append(
                    ReadinessReason(
                        code: "check-in.illness",
                        message: "Illness symptoms were reported this morning.",
                        direction: .caution,
                        priority: 95
                    )
                )
            }
            if checkIn.painWithMovement > 0 {
                reasons.append(
                    ReadinessReason(
                        code: "check-in.movement-pain",
                        message: "Pain with movement is \(checkIn.painWithMovement)/10.",
                        direction: .caution,
                        priority: 60 + checkIn.painWithMovement
                    )
                )
            }
            if checkIn.swelling || checkIn.perceivedWeakness {
                reasons.append(
                    ReadinessReason(
                        code: "check-in.tissue-signals",
                        message: "Swelling or perceived weakness was reported.",
                        direction: .caution,
                        priority: 88
                    )
                )
            }
        } else {
            reasons.append(
                Self.missing("check-in.missing", "Today’s morning check-in is incomplete.")
            )
        }

        for restriction in input.activeRestrictions {
            reasons.append(
                ReadinessReason(
                    code: "restriction.\(restriction.level.rawValue).\(restriction.id)",
                    message:
                        "\(restriction.injuryName): \(restriction.level.displayName.lowercased()) \(restriction.movementTag).",
                    direction: restriction.level.isHard ? .restriction : .caution,
                    priority: restriction.level.isHard ? 100 : 75
                )
            )
        }

        let recommendation = Self.recommendation(
            systemicScore: systemicScore,
            sleepScore: sleepScore,
            tissueScore: tissueScore,
            checkIn: input.checkIn,
            restrictions: input.activeRestrictions
        )
        let confidence = Self.confidence(
            input: input,
            hrvBaseline: hrvBaseline,
            sdnnBaseline: sdnnBaseline,
            heartRateBaseline: heartRateBaseline
        )

        return ReadinessAssessment(
            id: "assessment:\(input.day)",
            day: input.day,
            computedAt: .now,
            systemicScore: systemicScore,
            sleepScore: sleepScore,
            tissueScore: tissueScore,
            recommendation: recommendation,
            confidence: confidence,
            reasons: reasons.sorted { $0.priority > $1.priority },
            rulesetVersion: Self.rulesetVersion,
            userOverride: nil,
            overrideNote: nil
        )
    }

    private static func initialSystemicScore(_ input: ReadinessInput) -> Int? {
        if let recovery = input.physiology.whoopRecovery {
            guard let checkIn = input.checkIn else { return recovery }
            let subjectiveAdjustment = (checkIn.energy - 3) * 4 + (checkIn.motivation - 3) * 3
            return min(100, max(0, recovery + subjectiveAdjustment))
        }
        if let checkIn = input.checkIn {
            return (checkIn.energy * 20 + checkIn.motivation * 20) / 2
        }
        return nil
    }

    private static func tissueScore(
        _ checkIn: MorningCheckIn?,
        restrictions: [RestrictionProfile]
    ) -> Int? {
        guard let checkIn else { return nil }
        var score = 100
        score -= checkIn.painAtRest * 4
        score -= checkIn.painWithMovement * 7
        if checkIn.stiffness { score -= 10 }
        if checkIn.swelling { score -= 20 }
        if checkIn.perceivedWeakness { score -= 15 }
        let symptomScore = max(0, score)
        guard restrictions.contains(where: { $0.level.isHard }) else {
            return symptomScore
        }
        return min(symptomScore, hardRestrictionTissueScoreCeiling)
    }

    private static func applyHRVSignal(
        name: String,
        code: String,
        current: Double?,
        baseline: BaselineStatistic?,
        systemicScore: inout Int?,
        reasons: inout [ReadinessReason]
    ) {
        guard let current else { return }
        guard let baseline, baseline.observationCount >= 14 else {
            reasons.append(
                missing(
                    "\(code).baseline-building",
                    "\(name) needs 14 observations for a strong baseline."
                )
            )
            return
        }
        guard let deviation = baseline.robustDeviation(of: current) else { return }
        if deviation <= -1 {
            systemicScore = systemicScore.map { max(0, $0 - (deviation <= -2 ? 12 : 7)) }
            reasons.append(
                ReadinessReason(
                    code: "\(code).below-baseline",
                    message: "\(name) is below its 28-day median.",
                    direction: .caution,
                    priority: deviation <= -2 ? 85 : 65
                )
            )
        } else if deviation >= 1 {
            reasons.append(
                ReadinessReason(
                    code: "\(code).above-baseline",
                    message: "\(name) is above its 28-day median.",
                    direction: .positive,
                    priority: 30
                )
            )
        }
    }

    private static func applyRestingHeartRateSignal(
        current: Double?,
        baseline: BaselineStatistic?,
        systemicScore: inout Int?,
        reasons: inout [ReadinessReason]
    ) {
        guard let current else { return }
        guard let baseline, baseline.observationCount >= 14 else {
            reasons.append(
                missing(
                    "resting-heart-rate.baseline-building",
                    "Resting heart rate needs 14 observations for a strong baseline."
                )
            )
            return
        }
        guard let deviation = baseline.robustDeviation(of: current) else { return }
        if deviation >= 1 {
            systemicScore = systemicScore.map { max(0, $0 - (deviation >= 2 ? 12 : 7)) }
            reasons.append(
                ReadinessReason(
                    code: "resting-heart-rate.above-baseline",
                    message: "Resting heart rate is above its 28-day median.",
                    direction: .caution,
                    priority: deviation >= 2 ? 85 : 65
                )
            )
        }
    }

    private static func recommendation(
        systemicScore: Int?,
        sleepScore: Int?,
        tissueScore: Int?,
        checkIn: MorningCheckIn?,
        restrictions: [RestrictionProfile]
    ) -> ReadinessAssessment.Recommendation {
        if restrictions.contains(where: { $0.level.isHard }) { return .modify }
        if checkIn?.illnessSymptoms == true, (systemicScore ?? 0) < 50 {
            return .recoveryFocused
        }
        if let tissueScore, tissueScore < 40 { return .modify }
        if let systemicScore, systemicScore < 40 { return .recoveryFocused }
        if let systemicScore, systemicScore < 65 { return .proceedWithLimits }
        if let sleepScore, sleepScore < 70 { return .proceedWithLimits }
        if systemicScore == nil || tissueScore == nil { return .proceedWithLimits }
        return .proceed
    }

    private static func confidence(
        input: ReadinessInput,
        hrvBaseline: BaselineStatistic?,
        sdnnBaseline: BaselineStatistic?,
        heartRateBaseline: BaselineStatistic?
    ) -> ReadinessAssessment.Confidence {
        var available = 0
        if input.physiology.whoopRecovery != nil { available += 1 }
        if input.physiology.sleepMinutes != nil { available += 1 }
        if input.checkIn != nil { available += 1 }
        if (hrvBaseline?.observationCount ?? 0) >= 14 { available += 1 }
        if (sdnnBaseline?.observationCount ?? 0) >= 14 { available += 1 }
        if (heartRateBaseline?.observationCount ?? 0) >= 14 { available += 1 }
        if available >= 5 { return .high }
        if available >= 3 { return .moderate }
        return .low
    }

    private static func missing(_ code: String, _ message: String) -> ReadinessReason {
        ReadinessReason(code: code, message: message, direction: .missing, priority: 10)
    }
}
