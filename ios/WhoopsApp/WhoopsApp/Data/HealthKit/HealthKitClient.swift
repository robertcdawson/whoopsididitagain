import Foundation
@preconcurrency import HealthKit

final class HealthKitClient: HealthKitReading, @unchecked Sendable {
    private static let queryBatchSize = 500
    private static let historyWindowDays = 180

    private final class ObserverCompletion: @unchecked Sendable {
        private let completion: () -> Void

        init(_ completion: @escaping () -> Void) {
            self.completion = completion
        }

        func call() {
            completion()
        }
    }

    private let healthStore: HKHealthStore
    private let lock = NSLock()
    private var observersStarted = false
    private var observerQueries: [HKObserverQuery] = []

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAuthorization() async throws {
        guard isHealthDataAvailable else { throw AppError.healthDataUnavailable }
        try await healthStore.requestAuthorization(toShare: [], read: Set(Self.sampleTypes.values))
    }

    func anchoredChanges(
        for metric: HealthMetric,
        anchorData: Data?
    ) async throws -> HealthKitChangeBatch {
        guard let sampleType = Self.sampleTypes[metric] else {
            throw AppError.healthDataUnavailable
        }

        let anchor = try anchorData.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let historyStart = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: -Self.historyWindowDays,
            to: .now
        )
        let predicate = HKQuery.predicateForSamples(
            withStart: historyStart,
            end: nil,
            options: []
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType,
                predicate: predicate,
                anchor: anchor,
                limit: Self.queryBatchSize
            ) { _, samples, deletedObjects, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    guard let newAnchor else { throw AppError.invalidHealthKitResponse }
                    let archivedAnchor = try NSKeyedArchiver.archivedData(
                        withRootObject: newAnchor,
                        requiringSecureCoding: true
                    )
                    let snapshots = (samples ?? []).compactMap {
                        Self.snapshot(for: $0, metric: metric)
                    }
                    continuation.resume(
                        returning: HealthKitChangeBatch(
                            samples: snapshots,
                            deletedSampleIDs: (deletedObjects ?? []).map(\.uuid),
                            anchorData: archivedAnchor,
                            hasMore: (samples ?? []).count == Self.queryBatchSize
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            healthStore.execute(query)
        }
    }

    func startObserving(
        onChange: @escaping @Sendable (HealthMetric) async -> Void
    ) async {
        // Claim registration before the first await; another startup may enter while
        // background-delivery registration is suspended.
        let shouldStart = lock.withLock {
            guard !observersStarted else { return false }
            observersStarted = true
            return true
        }
        guard shouldStart else { return }

        var queries: [HKObserverQuery] = []
        for metric in HealthMetric.allCases {
            guard let sampleType = Self.sampleTypes[metric] else { continue }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) {
                _, completion, error in
                guard error == nil else {
                    completion()
                    return
                }
                let completion = ObserverCompletion(completion)
                Task {
                    defer { completion.call() }
                    await onChange(metric)
                }
            }
            healthStore.execute(query)
            try? await healthStore.enableBackgroundDelivery(
                for: sampleType,
                frequency: .hourly
            )
            queries.append(query)
        }
        lock.withLock { observerQueries = queries }
    }

    private static let sampleTypes: [HealthMetric: HKSampleType] = [
        .heartRate: HKQuantityType(.heartRate),
        .restingHeartRate: HKQuantityType(.restingHeartRate),
        .hrvSDNN: HKQuantityType(.heartRateVariabilitySDNN),
        .respiratoryRate: HKQuantityType(.respiratoryRate),
        .oxygenSaturation: HKQuantityType(.oxygenSaturation),
        .sleepAnalysis: HKCategoryType(.sleepAnalysis),
        .workout: HKWorkoutType.workoutType(),
        .activeEnergy: HKQuantityType(.activeEnergyBurned),
        .exerciseTime: HKQuantityType(.appleExerciseTime),
        .walkingRunningDistance: HKQuantityType(.distanceWalkingRunning),
        .cyclingDistance: HKQuantityType(.distanceCycling),
        .vo2Max: HKQuantityType(.vo2Max),
        .bodyMass: HKQuantityType(.bodyMass),
        .sleepingWristTemperature: HKQuantityType(.appleSleepingWristTemperature),
    ]

    private static func snapshot(
        for sample: HKSample,
        metric: HealthMetric
    ) -> HealthSampleSnapshot {
        let normalized = normalizedValue(for: sample, metric: metric)
        let timeZone = sampleTimeZone(for: sample)
        let categoryValue = (sample as? HKCategorySample)?.value
        let workout = sample as? HKWorkout

        return HealthSampleSnapshot(
            id: sample.uuid,
            metric: metric,
            startAt: sample.startDate,
            endAt: sample.endDate,
            value: normalized.value,
            unit: normalized.unit,
            categoryValue: categoryValue,
            workoutActivityType: workout.map { UInt($0.workoutActivityType.rawValue) },
            sourceName: sample.sourceRevision.source.name,
            sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
            timeZoneIdentifier: timeZone.identifier,
            timeZoneOffsetSeconds: timeZone.secondsFromGMT(for: sample.startDate),
            localDay: HealthDayKey.day(containing: sample.startDate, timeZone: timeZone)
        )
    }

    private static func normalizedValue(
        for sample: HKSample,
        metric: HealthMetric
    ) -> (value: Double?, unit: String?) {
        if metric == .sleepAnalysis, let category = sample as? HKCategorySample {
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            ]
            let minutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
            return (asleepValues.contains(category.value) ? minutes : nil, "min")
        }

        if let workout = sample as? HKWorkout {
            return (workout.duration / 60, "min")
        }

        guard let quantity = sample as? HKQuantitySample else { return (nil, nil) }
        let unit: HKUnit
        let label: String
        switch metric {
        case .heartRate, .restingHeartRate, .respiratoryRate:
            unit = HKUnit.count().unitDivided(by: .minute())
            label = "count/min"
        case .hrvSDNN:
            unit = .secondUnit(with: .milli)
            label = "ms"
        case .oxygenSaturation:
            return (quantity.quantity.doubleValue(for: .percent()) * 100, "%")
        case .activeEnergy:
            unit = .kilocalorie()
            label = "kcal"
        case .exerciseTime:
            unit = .minute()
            label = "min"
        case .walkingRunningDistance, .cyclingDistance:
            unit = .meter()
            label = "m"
        case .vo2Max:
            unit = HKUnit(from: "ml/kg*min")
            label = "mL/kg/min"
        case .bodyMass:
            unit = .gramUnit(with: .kilo)
            label = "kg"
        case .sleepingWristTemperature:
            unit = .degreeCelsius()
            label = "degC"
        case .sleepAnalysis, .workout:
            return (nil, nil)
        }
        return (quantity.quantity.doubleValue(for: unit), label)
    }

    private static func sampleTimeZone(for sample: HKSample) -> TimeZone {
        if let identifier = sample.metadata?[HKMetadataKeyTimeZone] as? String,
            let timeZone = TimeZone(identifier: identifier)
        {
            return timeZone
        }
        return .autoupdatingCurrent
    }
}
