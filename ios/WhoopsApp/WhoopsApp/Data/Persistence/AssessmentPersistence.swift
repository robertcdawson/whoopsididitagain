import Foundation
import SwiftData

@Model
final class InjuryRecord {
    @Attribute(.unique) var id: String
    var name: String
    var bodyRegion: String
    var side: String
    var status: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        bodyRegion: String,
        side: String,
        status: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.bodyRegion = bodyRegion
        self.side = side
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class RestrictionRecord {
    @Attribute(.unique) var id: String
    var injuryID: String
    var movementTag: String
    var level: String
    var painThreshold: Int
    var rationale: String
    var isActive: Bool
    var updatedAt: Date

    init(profile: RestrictionProfile, injuryID: String, updatedAt: Date) {
        id = profile.id
        self.injuryID = injuryID
        movementTag = profile.movementTag
        level = profile.level.rawValue
        painThreshold = profile.painThreshold
        rationale = profile.rationale
        isActive = profile.isActive
        self.updatedAt = updatedAt
    }
}

@Model
final class SymptomCheckInRecord {
    @Attribute(.unique) var id: String
    var day: String
    var timestamp: Date
    var painAtRest: Int
    var painWithMovement: Int
    var stiffness: Bool
    var swelling: Bool
    var perceivedWeakness: Bool
    var energy: Int
    var motivation: Int
    var illnessSymptoms: Bool
    var notes: String

    init(checkIn: MorningCheckIn) {
        id = "check-in:\(checkIn.day)"
        day = checkIn.day
        timestamp = checkIn.timestamp
        painAtRest = checkIn.painAtRest
        painWithMovement = checkIn.painWithMovement
        stiffness = checkIn.stiffness
        swelling = checkIn.swelling
        perceivedWeakness = checkIn.perceivedWeakness
        energy = checkIn.energy
        motivation = checkIn.motivation
        illnessSymptoms = checkIn.illnessSymptoms
        notes = checkIn.notes
    }

    func update(from checkIn: MorningCheckIn) {
        timestamp = checkIn.timestamp
        painAtRest = checkIn.painAtRest
        painWithMovement = checkIn.painWithMovement
        stiffness = checkIn.stiffness
        swelling = checkIn.swelling
        perceivedWeakness = checkIn.perceivedWeakness
        energy = checkIn.energy
        motivation = checkIn.motivation
        illnessSymptoms = checkIn.illnessSymptoms
        notes = checkIn.notes
    }
}

@Model
final class ReadinessAssessmentRecord {
    @Attribute(.unique) var id: String
    var day: String
    var computedAt: Date
    var systemicScore: Int?
    var sleepScore: Int?
    var tissueScore: Int?
    var recommendation: String
    var confidence: String
    var reasonsData: Data
    var rulesetVersion: String
    var userOverride: String?
    var overrideNote: String?

    init(assessment: ReadinessAssessment, reasonsData: Data) {
        id = assessment.id
        day = assessment.day
        computedAt = assessment.computedAt
        systemicScore = assessment.systemicScore
        sleepScore = assessment.sleepScore
        tissueScore = assessment.tissueScore
        recommendation = assessment.recommendation.rawValue
        confidence = assessment.confidence.rawValue
        self.reasonsData = reasonsData
        rulesetVersion = assessment.rulesetVersion
        userOverride = assessment.userOverride?.rawValue
        overrideNote = assessment.overrideNote
    }
}

@Model
final class SleepScheduleRecord {
    @Attribute(.unique) var id: String
    var wakeHour: Int
    var wakeMinute: Int
    var targetSleepMinutes: Int
    var sleepLatencyMinutes: Int
    var windDownMinutes: Int

    init(settings: SleepScheduleSettings) {
        id = "sleep-schedule:primary"
        wakeHour = settings.wakeHour
        wakeMinute = settings.wakeMinute
        targetSleepMinutes = settings.targetSleepMinutes
        sleepLatencyMinutes = settings.sleepLatencyMinutes
        windDownMinutes = settings.windDownMinutes
    }
}

@MainActor
final class AssessmentPersistence: AssessmentRepository, @unchecked Sendable {
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func prepareDefaults() async throws {
        if try context.fetchCount(FetchDescriptor<RestrictionRecord>()) == 0 {
            for profile in Self.defaultRestrictions {
                try await saveRestriction(profile)
            }
        }
        if try context.fetchCount(FetchDescriptor<SleepScheduleRecord>()) == 0 {
            context.insert(SleepScheduleRecord(settings: .standard))
            try context.save()
        }
    }

    func checkIn(for day: String) async throws -> MorningCheckIn? {
        try context.fetch(FetchDescriptor<SymptomCheckInRecord>())
            .first(where: { $0.day == day })
            .map(Self.checkIn)
    }

    func saveCheckIn(_ checkIn: MorningCheckIn) async throws {
        let id = "check-in:\(checkIn.day)"
        if let existing = try context.fetch(FetchDescriptor<SymptomCheckInRecord>())
            .first(where: { $0.id == id })
        {
            existing.update(from: checkIn)
        } else {
            context.insert(SymptomCheckInRecord(checkIn: checkIn))
        }
        try context.save()
    }

    func restrictions() async throws -> [RestrictionProfile] {
        let injuries = try context.fetch(FetchDescriptor<InjuryRecord>())
        let injuriesByID = Dictionary(uniqueKeysWithValues: injuries.map { ($0.id, $0) })
        return try context.fetch(FetchDescriptor<RestrictionRecord>())
            .compactMap { restriction in
                guard let injury = injuriesByID[restriction.injuryID],
                    let level = RestrictionLevel(rawValue: restriction.level)
                else { return nil }
                return RestrictionProfile(
                    id: restriction.id,
                    injuryName: injury.name,
                    bodyRegion: injury.bodyRegion,
                    side: injury.side,
                    movementTag: restriction.movementTag,
                    level: level,
                    painThreshold: restriction.painThreshold,
                    rationale: restriction.rationale,
                    isActive: restriction.isActive
                )
            }
            .sorted { $0.injuryName < $1.injuryName }
    }

    func saveRestriction(_ profile: RestrictionProfile) async throws {
        let existingRestrictions = try context.fetch(FetchDescriptor<RestrictionRecord>())
        let existingInjuries = try context.fetch(FetchDescriptor<InjuryRecord>())
        let injuryID = "injury:\(profile.id)"
        let now = Date.now
        if let injury = existingInjuries.first(where: { $0.id == injuryID }) {
            injury.name = profile.injuryName
            injury.bodyRegion = profile.bodyRegion
            injury.side = profile.side
            injury.status = profile.isActive ? "active" : "managed"
            injury.updatedAt = now
        } else {
            context.insert(
                InjuryRecord(
                    id: injuryID,
                    name: profile.injuryName,
                    bodyRegion: profile.bodyRegion,
                    side: profile.side,
                    status: profile.isActive ? "active" : "managed",
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        if let restriction = existingRestrictions.first(where: { $0.id == profile.id }) {
            restriction.movementTag = profile.movementTag
            restriction.level = profile.level.rawValue
            restriction.painThreshold = profile.painThreshold
            restriction.rationale = profile.rationale
            restriction.isActive = profile.isActive
            restriction.updatedAt = now
        } else {
            context.insert(RestrictionRecord(profile: profile, injuryID: injuryID, updatedAt: now))
        }
        try context.save()
    }

    func deleteRestriction(id: String) async throws {
        if let restriction = try context.fetch(FetchDescriptor<RestrictionRecord>())
            .first(where: { $0.id == id })
        {
            context.delete(restriction)
        }
        if let injury = try context.fetch(FetchDescriptor<InjuryRecord>())
            .first(where: { $0.id == "injury:\(id)" })
        {
            context.delete(injury)
        }
        try context.save()
    }

    func sleepSettings() async throws -> SleepScheduleSettings {
        guard let record = try context.fetch(FetchDescriptor<SleepScheduleRecord>()).first else {
            return .standard
        }
        return SleepScheduleSettings(
            wakeHour: record.wakeHour,
            wakeMinute: record.wakeMinute,
            targetSleepMinutes: record.targetSleepMinutes,
            sleepLatencyMinutes: record.sleepLatencyMinutes,
            windDownMinutes: record.windDownMinutes
        )
    }

    func saveSleepSettings(_ settings: SleepScheduleSettings) async throws {
        if let record = try context.fetch(FetchDescriptor<SleepScheduleRecord>()).first {
            record.wakeHour = settings.wakeHour
            record.wakeMinute = settings.wakeMinute
            record.targetSleepMinutes = settings.targetSleepMinutes
            record.sleepLatencyMinutes = settings.sleepLatencyMinutes
            record.windDownMinutes = settings.windDownMinutes
        } else {
            context.insert(SleepScheduleRecord(settings: settings))
        }
        try context.save()
    }

    func assessment(for day: String) async throws -> ReadinessAssessment? {
        guard
            let record = try context.fetch(FetchDescriptor<ReadinessAssessmentRecord>())
                .first(where: { $0.day == day }),
            let recommendation = ReadinessAssessment.Recommendation(
                rawValue: record.recommendation),
            let confidence = ReadinessAssessment.Confidence(rawValue: record.confidence),
            let reasons = try? decoder.decode([ReadinessReason].self, from: record.reasonsData)
        else { return nil }
        return ReadinessAssessment(
            id: record.id,
            day: record.day,
            computedAt: record.computedAt,
            systemicScore: record.systemicScore,
            sleepScore: record.sleepScore,
            tissueScore: record.tissueScore,
            recommendation: recommendation,
            confidence: confidence,
            reasons: reasons,
            rulesetVersion: record.rulesetVersion,
            userOverride: record.userOverride.flatMap(ReadinessAssessment.Recommendation.init),
            overrideNote: record.overrideNote
        )
    }

    func saveAssessment(_ assessment: ReadinessAssessment) async throws {
        let reasonsData = try encoder.encode(assessment.reasons)
        if let record = try context.fetch(FetchDescriptor<ReadinessAssessmentRecord>())
            .first(where: { $0.id == assessment.id })
        {
            record.computedAt = assessment.computedAt
            record.systemicScore = assessment.systemicScore
            record.sleepScore = assessment.sleepScore
            record.tissueScore = assessment.tissueScore
            record.recommendation = assessment.recommendation.rawValue
            record.confidence = assessment.confidence.rawValue
            record.reasonsData = reasonsData
            record.rulesetVersion = assessment.rulesetVersion
        } else {
            context.insert(
                ReadinessAssessmentRecord(assessment: assessment, reasonsData: reasonsData)
            )
        }
        try context.save()
    }

    func saveOverride(
        assessmentID: String,
        recommendation: ReadinessAssessment.Recommendation?,
        note: String?
    ) async throws {
        guard
            let record = try context.fetch(FetchDescriptor<ReadinessAssessmentRecord>())
                .first(where: { $0.id == assessmentID })
        else { return }
        record.userOverride = recommendation?.rawValue
        record.overrideNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    private static func checkIn(_ record: SymptomCheckInRecord) -> MorningCheckIn {
        MorningCheckIn(
            day: record.day,
            timestamp: record.timestamp,
            painAtRest: record.painAtRest,
            painWithMovement: record.painWithMovement,
            stiffness: record.stiffness,
            swelling: record.swelling,
            perceivedWeakness: record.perceivedWeakness,
            energy: record.energy,
            motivation: record.motivation,
            illnessSymptoms: record.illnessSymptoms,
            notes: record.notes
        )
    }

    private static let defaultRestrictions: [RestrictionProfile] = [
        RestrictionProfile(
            id: "right-distal-triceps",
            injuryName: "Right distal triceps",
            bodyRegion: "Elbow / upper arm",
            side: "Right",
            movementTag: "ballistic or painful elbow extension",
            level: .avoid,
            painThreshold: 2,
            rationale:
                "Known partial distal-triceps injury; keep this editable as guidance changes.",
            isActive: true
        ),
        RestrictionProfile(
            id: "left-triceps",
            injuryName: "Left triceps",
            bodyRegion: "Upper arm",
            side: "Left",
            movementTag: "painful elbow extension",
            level: .monitor,
            painThreshold: 2,
            rationale: "Monitor symptoms and update if tolerance changes.",
            isActive: false
        ),
        RestrictionProfile(
            id: "low-back",
            injuryName: "Low back",
            bodyRegion: "Lumbar spine",
            side: "Midline",
            movementTag: "painful spinal flexion or compression",
            level: .limit,
            painThreshold: 3,
            rationale: "Use during episodic irritation.",
            isActive: false
        ),
        RestrictionProfile(
            id: "left-acl-history",
            injuryName: "Left ACL history",
            bodyRegion: "Knee",
            side: "Left",
            movementTag: "painful high-impact knee loading",
            level: .monitor,
            painThreshold: 3,
            rationale: "Historical surgery; activate only when symptoms warrant it.",
            isActive: false
        ),
        RestrictionProfile(
            id: "foot-arch-calf",
            injuryName: "Foot arch / calf",
            bodyRegion: "Lower leg / foot",
            side: "Either",
            movementTag: "painful running or high-impact loading",
            level: .monitor,
            painThreshold: 3,
            rationale: "Use during recurring arch or calf symptoms.",
            isActive: false
        ),
    ]
}
