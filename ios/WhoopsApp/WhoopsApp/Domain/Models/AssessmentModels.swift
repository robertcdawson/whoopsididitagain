import Foundation

enum RestrictionLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case monitor
    case limit
    case avoid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .monitor: "Monitor"
        case .limit: "Limit"
        case .avoid: "Avoid"
        }
    }

    var isHard: Bool { self == .avoid }
}

struct RestrictionProfile: Identifiable, Equatable, Sendable {
    let id: String
    var injuryName: String
    var bodyRegion: String
    var side: String
    var affectedAreaIDs: [String]
    var movementTag: String
    var level: RestrictionLevel
    var painThreshold: Int
    var rationale: String
    var isActive: Bool

    init(
        id: String,
        injuryName: String,
        bodyRegion: String,
        side: String,
        affectedAreaIDs: [String] = [],
        movementTag: String,
        level: RestrictionLevel,
        painThreshold: Int,
        rationale: String,
        isActive: Bool
    ) {
        self.id = id
        self.injuryName = injuryName
        self.bodyRegion = bodyRegion
        self.side = side
        self.affectedAreaIDs = BodyAreaCatalog.validIDs(affectedAreaIDs)
        self.movementTag = movementTag
        self.level = level
        self.painThreshold = painThreshold
        self.rationale = rationale
        self.isActive = isActive
    }
}

enum BodyMapSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case left
    case right
    case midline

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum BodyMapView: String, Codable, CaseIterable, Identifiable, Sendable {
    case front
    case back

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum BodyMapRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case headNeck = "head-neck"
    case arm
    case torso
    case leg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .headNeck: "Head & neck"
        case .arm: "Arm"
        case .torso: "Torso"
        case .leg: "Leg"
        }
    }
}

struct BodyMapFocus: Hashable, Identifiable, Sendable {
    let region: BodyMapRegion
    let side: BodyMapSide

    var id: String { "\(side.rawValue).\(region.rawValue)" }

    var displayName: String {
        if side == .midline { return region.displayName }
        return "\(side.displayName) \(region.displayName.lowercased())"
    }
}

struct BodyAreaDefinition: Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let shortLabel: String
    let focus: BodyMapFocus
    let view: BodyMapView?
    let order: Int
    let isWholeFocus: Bool
    let supportsFigureTap: Bool

    var viewLabel: String? { view?.displayName }
}

enum BodyAreaCatalog {
    static let all: [BodyAreaDefinition] = {
        var areas: [BodyAreaDefinition] = [
            area(
                "midline.head-neck.entire", "Entire head and neck", "Entire head & neck",
                .headNeck, .midline, nil, 0, isWholeFocus: true),
            area(
                "midline.head-neck.head", "Head / scalp", "Head / scalp", .headNeck, .midline, nil,
                1),
            area("midline.head-neck.face", "Face", "Face", .headNeck, .midline, .front, 2),
            area(
                "midline.head-neck.eye.left", "Left eye / orbit", "Left eye / orbit",
                .headNeck, .midline, .front, 3),
            area(
                "midline.head-neck.eye.right", "Right eye / orbit", "Right eye / orbit",
                .headNeck, .midline, .front, 4),
            area(
                "midline.head-neck.ear.left", "Left ear", "Left ear", .headNeck, .midline,
                .front, 5),
            area(
                "midline.head-neck.ear.right", "Right ear", "Right ear", .headNeck, .midline,
                .front, 6),
            area(
                "midline.head-neck.nose-sinus", "Nose / sinus area", "Nose / sinus area",
                .headNeck, .midline, .front, 7),
            area(
                "midline.head-neck.jaw-chin", "Jaw / chin", "Jaw / chin", .headNeck,
                .midline, .front, 8),
            area(
                "midline.head-neck.mouth", "Mouth", "Mouth", .headNeck, .midline, .front,
                9),
            area(
                "midline.head-neck.neck.front", "Front of neck", "Front of neck", .headNeck,
                .midline, .front, 10),
            area(
                "midline.head-neck.neck.left", "Left side of neck", "Left side of neck",
                .headNeck, .midline, .front, 11),
            area(
                "midline.head-neck.neck.right", "Right side of neck", "Right side of neck",
                .headNeck, .midline, .front, 12),
            area(
                "midline.head-neck.head.back", "Back of head", "Back of head", .headNeck,
                .midline, .back, 13),
            area(
                "midline.head-neck.neck.back", "Back of neck", "Back of neck", .headNeck, .midline,
                .back, 14),
            area(
                "midline.torso.entire", "Entire torso", "Entire torso", .torso, .midline, nil,
                0, isWholeFocus: true),
            area(
                "midline.torso.chest", "Chest / thorax", "Chest / thorax", .torso, .midline, .front,
                1),
            area(
                "midline.torso.chest.left", "Left chest / ribs", "Left chest / ribs", .torso,
                .midline, .front, 2),
            area(
                "midline.torso.chest.right", "Right chest / ribs", "Right chest / ribs",
                .torso, .midline, .front, 3),
            area(
                "midline.torso.sternum", "Sternum / breastbone", "Sternum / breastbone",
                .torso, .midline, .front, 4),
            area("midline.torso.abdomen", "Abdomen", "Abdomen", .torso, .midline, .front, 5),
            area(
                "midline.torso.flank.left.front", "Left front flank", "Left front flank",
                .torso, .midline, .front, 6),
            area(
                "midline.torso.flank.right.front", "Right front flank", "Right front flank",
                .torso, .midline, .front, 7),
            area(
                "midline.torso.pelvis-hip.front", "Front pelvis / hip", "Front pelvis / hip",
                .torso, .midline, .front, 8),
            area(
                "midline.torso.groin.left", "Left groin", "Left groin", .torso, .midline,
                .front, 9),
            area(
                "midline.torso.groin.right", "Right groin", "Right groin", .torso, .midline,
                .front, 10),
            area(
                "midline.torso.pelvic-floor", "Pelvic floor / perineum",
                "Pelvic floor / perineum", .torso, .midline, .front, 11),
            area(
                "midline.torso.upper-back", "Upper back", "Upper back", .torso, .midline, .back, 12),
            area(
                "midline.torso.shoulder-blade.left", "Left shoulder blade",
                "Left shoulder blade", .torso, .midline, .back, 13),
            area(
                "midline.torso.shoulder-blade.right", "Right shoulder blade",
                "Right shoulder blade", .torso, .midline, .back, 14),
            area("midline.torso.mid-back", "Mid back", "Mid back", .torso, .midline, .back, 15),
            area(
                "midline.torso.flank.left.back", "Left back flank", "Left back flank", .torso,
                .midline, .back, 16),
            area(
                "midline.torso.flank.right.back", "Right back flank", "Right back flank",
                .torso, .midline, .back, 17),
            area(
                "midline.torso.lower-back", "Lower back", "Lower back", .torso, .midline, .back, 18),
            area(
                "midline.torso.sacrum-tailbone", "Sacrum / tailbone", "Sacrum / tailbone",
                .torso, .midline, .back, 19),
            area(
                "midline.torso.pelvis-hip.back", "Back pelvis / hip", "Back pelvis / hip", .torso,
                .midline, .back, 20),
            area(
                "midline.torso.glute.left", "Left buttock / glute", "Left buttock / glute",
                .torso, .midline, .back, 21),
            area(
                "midline.torso.glute.right", "Right buttock / glute", "Right buttock / glute",
                .torso, .midline, .back, 22),
            area(
                "midline.torso.collarbone.left", "Left collarbone / clavicle",
                "Left collarbone / clavicle", .torso, .midline, .front, 23),
            area(
                "midline.torso.collarbone.right", "Right collarbone / clavicle",
                "Right collarbone / clavicle", .torso, .midline, .front, 24),
            area(
                "midline.torso.hip.left", "Left hip", "Left hip", .torso, .midline, .front,
                25),
            area(
                "midline.torso.hip.right", "Right hip", "Right hip", .torso, .midline,
                .front, 26),
            area(
                "midline.torso.si-joint.left", "Left sacroiliac (SI) joint area",
                "Left SI joint area", .torso, .midline, .back, 27),
            area(
                "midline.torso.si-joint.right", "Right sacroiliac (SI) joint area",
                "Right SI joint area", .torso, .midline, .back, 28),
        ]

        for side in [BodyMapSide.left, .right] {
            let sideName = side.displayName
            let prefix = side.rawValue
            areas.append(contentsOf: [
                area(
                    "\(prefix).arm.entire", "Entire \(sideName.lowercased()) arm", "Entire arm",
                    .arm, side, nil, 0, isWholeFocus: true),
                area(
                    "\(prefix).arm.shoulder.front", "\(sideName) front shoulder", "Front shoulder",
                    .arm, side, .front, 1, supportsFigureTap: true),
                area(
                    "\(prefix).arm.armpit", "\(sideName) armpit / axilla", "Armpit / axilla",
                    .arm, side, .front, 2),
                area(
                    "\(prefix).arm.upper-arm.front", "\(sideName) anterior upper arm",
                    "Anterior upper arm (biceps area)", .arm, side, .front, 3,
                    supportsFigureTap: true),
                area(
                    "\(prefix).arm.upper-arm.inner", "\(sideName) inner upper arm",
                    "Inner upper arm", .arm, side, .front, 4),
                area(
                    "\(prefix).arm.upper-arm.outer", "\(sideName) outer upper arm",
                    "Outer upper arm", .arm, side, .front, 5),
                area(
                    "\(prefix).arm.elbow.front", "\(sideName) front elbow", "Front elbow", .arm,
                    side, .front, 6, supportsFigureTap: true),
                area(
                    "\(prefix).arm.elbow.inner", "\(sideName) inner elbow", "Inner elbow", .arm,
                    side, .front, 7),
                area(
                    "\(prefix).arm.elbow.outer", "\(sideName) outer elbow", "Outer elbow", .arm,
                    side, .front, 8),
                area(
                    "\(prefix).arm.forearm.front", "\(sideName) anterior forearm",
                    "Anterior forearm", .arm, side, .front, 9, supportsFigureTap: true),
                area(
                    "\(prefix).arm.forearm.inner", "\(sideName) inner forearm",
                    "Inner forearm", .arm, side, .front, 10),
                area(
                    "\(prefix).arm.forearm.outer", "\(sideName) outer forearm",
                    "Outer forearm", .arm, side, .front, 11),
                area(
                    "\(prefix).arm.wrist-hand.front", "\(sideName) palm / wrist", "Palm / wrist",
                    .arm, side, .front, 12, supportsFigureTap: true),
                area(
                    "\(prefix).arm.thumb", "\(sideName) thumb", "Thumb", .arm, side, .front,
                    13),
                area(
                    "\(prefix).arm.fingers", "\(sideName) fingers", "Fingers", .arm, side,
                    .front, 14),
                area(
                    "\(prefix).arm.shoulder.back", "\(sideName) back shoulder", "Back shoulder",
                    .arm, side, .back, 15, supportsFigureTap: true),
                area(
                    "\(prefix).arm.upper-arm.back",
                    "\(sideName) posterior upper arm (triceps area)",
                    "Posterior upper arm (triceps area)",
                    .arm,
                    side,
                    .back,
                    16,
                    supportsFigureTap: true),
                area(
                    "\(prefix).arm.elbow.back", "\(sideName) back elbow", "Back elbow", .arm, side,
                    .back, 17, supportsFigureTap: true),
                area(
                    "\(prefix).arm.forearm.back", "\(sideName) posterior forearm",
                    "Posterior forearm", .arm, side, .back, 18, supportsFigureTap: true),
                area(
                    "\(prefix).arm.wrist-hand.back", "\(sideName) back of hand / wrist",
                    "Back of hand / wrist", .arm, side, .back, 19, supportsFigureTap: true),
                area(
                    "\(prefix).leg.entire", "Entire \(sideName.lowercased()) leg", "Entire leg",
                    .leg, side, nil, 0, isWholeFocus: true),
                area(
                    "\(prefix).leg.thigh.front", "\(sideName) anterior thigh", "Anterior thigh",
                    .leg, side, .front, 3),
                area(
                    "\(prefix).leg.thigh.inner", "\(sideName) inner thigh", "Inner thigh", .leg,
                    side, .front, 4),
                area(
                    "\(prefix).leg.thigh.outer", "\(sideName) outer thigh", "Outer thigh", .leg,
                    side, .front, 5),
                area(
                    "\(prefix).leg.knee.front", "\(sideName) front knee", "Front knee", .leg, side,
                    .front, 6),
                area(
                    "\(prefix).leg.knee.inner", "\(sideName) inner knee", "Inner knee", .leg,
                    side, .front, 7),
                area(
                    "\(prefix).leg.knee.outer", "\(sideName) outer knee", "Outer knee", .leg,
                    side, .front, 8),
                area(
                    "\(prefix).leg.lower-leg.front", "\(sideName) anterior lower leg",
                    "Shin / anterior lower leg", .leg, side, .front, 9),
                area(
                    "\(prefix).leg.lower-leg.inner", "\(sideName) inner lower leg",
                    "Inner lower leg", .leg, side, .front, 10),
                area(
                    "\(prefix).leg.lower-leg.outer", "\(sideName) outer lower leg",
                    "Outer lower leg", .leg, side, .front, 11),
                area(
                    "\(prefix).leg.ankle-foot.front", "\(sideName) front ankle / foot",
                    "Front ankle / top of foot", .leg, side, .front, 12),
                area(
                    "\(prefix).leg.ankle.inner", "\(sideName) inner ankle", "Inner ankle", .leg,
                    side, .front, 13),
                area(
                    "\(prefix).leg.ankle.outer", "\(sideName) outer ankle", "Outer ankle", .leg,
                    side, .front, 14),
                area(
                    "\(prefix).leg.toes", "\(sideName) toes", "Toes", .leg, side, .front, 15),
                area(
                    "\(prefix).leg.thigh.back", "\(sideName) posterior thigh", "Posterior thigh",
                    .leg, side, .back, 17),
                area(
                    "\(prefix).leg.knee.back", "\(sideName) back knee", "Back knee", .leg, side,
                    .back, 18),
                area(
                    "\(prefix).leg.lower-leg.back", "\(sideName) posterior lower leg",
                    "Calf / posterior lower leg", .leg, side, .back, 19),
                area(
                    "\(prefix).leg.ankle-foot.back", "\(sideName) back ankle / foot",
                    "Achilles / back ankle", .leg, side, .back, 20),
                area(
                    "\(prefix).leg.heel", "\(sideName) heel", "Heel", .leg, side, .back, 21),
                area(
                    "\(prefix).leg.sole-arch", "\(sideName) sole / foot arch",
                    "Sole / foot arch", .leg, side, .back, 22),
                area(
                    "\(prefix).leg.ball-foot", "\(sideName) ball of foot / forefoot",
                    "Ball of foot / forefoot", .leg, side, .back, 23),
            ])
        }
        return areas
    }()

    private static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func definition(for id: String) -> BodyAreaDefinition? { byID[id] }

    static func definitions(for ids: [String]) -> [BodyAreaDefinition] {
        validIDs(ids).compactMap { byID[$0] }
    }

    static func validIDs(_ ids: [String]) -> [String] {
        Array(Set(ids.filter { byID[$0] != nil })).sorted { lhs, rhs in
            guard let left = byID[lhs], let right = byID[rhs] else { return lhs < rhs }
            if left.focus.id != right.focus.id { return left.focus.id < right.focus.id }
            return left.order < right.order
        }
    }

    static func areas(for focus: BodyMapFocus, view: BodyMapView) -> [BodyAreaDefinition] {
        all.filter { $0.focus == focus && ($0.view == nil || $0.view == view) }
            .sorted { $0.order < $1.order }
    }

    static func figureAreas(for focus: BodyMapFocus, view: BodyMapView) -> [BodyAreaDefinition] {
        areas(for: focus, view: view).filter(\.supportsFigureTap)
    }

    static func focuses(for view: BodyMapView) -> [BodyMapFocus] {
        [
            BodyMapFocus(region: .headNeck, side: .midline),
            BodyMapFocus(region: .arm, side: .left),
            BodyMapFocus(region: .arm, side: .right),
            BodyMapFocus(region: .torso, side: .midline),
            BodyMapFocus(region: .leg, side: .left),
            BodyMapFocus(region: .leg, side: .right),
        ].filter { focus in
            all.contains { $0.focus == focus && ($0.view == nil || $0.view == view) }
        }
    }

    static func containsSelection(
        in focus: BodyMapFocus,
        selectedIDs: Set<String>
    ) -> Bool {
        all.contains { selectedIDs.contains($0.id) && $0.focus == focus }
    }

    private static func area(
        _ id: String,
        _ label: String,
        _ shortLabel: String,
        _ region: BodyMapRegion,
        _ side: BodyMapSide,
        _ view: BodyMapView?,
        _ order: Int,
        isWholeFocus: Bool = false,
        supportsFigureTap: Bool = false
    ) -> BodyAreaDefinition {
        BodyAreaDefinition(
            id: id,
            label: label,
            shortLabel: shortLabel,
            focus: BodyMapFocus(region: region, side: side),
            view: view,
            order: order,
            isWholeFocus: isWholeFocus,
            supportsFigureTap: supportsFigureTap
        )
    }
}

struct MorningCheckIn: Equatable, Sendable {
    let day: String
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

    static func empty(day: String, timestamp: Date = .now) -> MorningCheckIn {
        MorningCheckIn(
            day: day,
            timestamp: timestamp,
            painAtRest: 0,
            painWithMovement: 0,
            stiffness: false,
            swelling: false,
            perceivedWeakness: false,
            energy: 3,
            motivation: 3,
            illnessSymptoms: false,
            notes: ""
        )
    }
}

struct SleepScheduleSettings: Equatable, Sendable {
    var wakeHour: Int
    var wakeMinute: Int
    var targetSleepMinutes: Int
    var sleepLatencyMinutes: Int
    var windDownMinutes: Int

    static let standard = SleepScheduleSettings(
        wakeHour: 7,
        wakeMinute: 15,
        targetSleepMinutes: 8 * 60,
        sleepLatencyMinutes: 20,
        windDownMinutes: 45
    )
}

struct SleepDeadline: Equatable, Sendable {
    let wakeAt: Date
    let lightsOutAt: Date
    let windDownAt: Date
}

struct BaselineStatistic: Equatable, Sendable {
    let median: Double
    let medianAbsoluteDeviation: Double
    let observationCount: Int

    func robustDeviation(of value: Double) -> Double? {
        guard medianAbsoluteDeviation > 0 else {
            return value == median ? 0 : nil
        }
        return (value - median) / (1.4826 * medianAbsoluteDeviation)
    }
}

struct PhysiologyReadinessInput: Equatable, Sendable {
    let whoopRecovery: Int?
    let whoopHRVRMSSD: Double?
    let whoopHRVHistory: [Double]
    let appleHRVSDNN: Double?
    let appleHRVHistory: [Double]
    let restingHeartRate: Double?
    let restingHeartRateHistory: [Double]
    let sleepMinutes: Int?
}

struct ReadinessInput: Equatable, Sendable {
    let date: Date
    let day: String
    let physiology: PhysiologyReadinessInput
    let checkIn: MorningCheckIn?
    let activeRestrictions: [RestrictionProfile]
    let sleepSettings: SleepScheduleSettings
}

struct ReadinessReason: Codable, Equatable, Identifiable, Sendable {
    enum Direction: String, Codable, Sendable {
        case positive
        case caution
        case restriction
        case missing
    }

    let code: String
    let message: String
    let direction: Direction
    let priority: Int

    var id: String { code }
}

struct ReadinessAssessment: Equatable, Sendable {
    enum Recommendation: String, Codable, CaseIterable, Identifiable, Sendable {
        case proceed
        case proceedWithLimits
        case modify
        case recoveryFocused

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .proceed: "Proceed"
            case .proceedWithLimits: "Proceed with limits"
            case .modify: "Modify"
            case .recoveryFocused: "Recovery-focused day"
            }
        }

        var symbolName: String {
            switch self {
            case .proceed: "checkmark.circle.fill"
            case .proceedWithLimits: "gauge.with.dots.needle.50percent"
            case .modify: "slider.horizontal.3"
            case .recoveryFocused: "bed.double.fill"
            }
        }
    }

    enum Confidence: String, Codable, Sendable {
        case low
        case moderate
        case high

        var displayName: String { rawValue.capitalized }
    }

    let id: String
    let day: String
    let computedAt: Date
    let systemicScore: Int?
    let sleepScore: Int?
    let tissueScore: Int?
    let recommendation: Recommendation
    let confidence: Confidence
    let reasons: [ReadinessReason]
    let rulesetVersion: String
    var userOverride: Recommendation?
    var overrideNote: String?

    var effectiveRecommendation: Recommendation {
        userOverride ?? recommendation
    }

    var reasonCodes: [String] { reasons.map(\.code) }
}

enum RobustBaseline {
    static func calculate(_ values: [Double], maximumCount: Int = 28) -> BaselineStatistic? {
        let values = Array(values.suffix(maximumCount)).filter(\.isFinite).sorted()
        guard !values.isEmpty else { return nil }
        let medianValue = median(values)
        let deviations = values.map { abs($0 - medianValue) }.sorted()
        return BaselineStatistic(
            median: medianValue,
            medianAbsoluteDeviation: median(deviations),
            observationCount: values.count
        )
    }

    private static func median(_ sortedValues: [Double]) -> Double {
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middle - 1] + sortedValues[middle]) / 2
        }
        return sortedValues[middle]
    }
}

enum SleepDeadlineCalculator {
    static func calculate(
        now: Date,
        settings: SleepScheduleSettings,
        calendar: Calendar = .autoupdatingCurrent
    ) -> SleepDeadline {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = settings.wakeHour
        components.minute = settings.wakeMinute
        components.second = 0
        var wakeAt = calendar.date(from: components) ?? now
        if wakeAt <= now {
            wakeAt = calendar.date(byAdding: .day, value: 1, to: wakeAt) ?? wakeAt
        }
        let lightsOutAt =
            calendar.date(
                byAdding: .minute,
                value: -(settings.targetSleepMinutes + settings.sleepLatencyMinutes),
                to: wakeAt
            ) ?? wakeAt
        let windDownAt =
            calendar.date(
                byAdding: .minute,
                value: -settings.windDownMinutes,
                to: lightsOutAt
            ) ?? lightsOutAt
        return SleepDeadline(wakeAt: wakeAt, lightsOutAt: lightsOutAt, windDownAt: windDownAt)
    }
}
