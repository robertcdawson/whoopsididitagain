import XCTest

@testable import WhoopsApp

final class OnDeviceWorkoutParserTests: XCTestCase {
    func testApplePrototypeIsUnavailableInNormalRuns() {
        XCTAssertFalse(FeatureFlags.appleWorkoutParserTestModeEnabled(environment: [:]))
        XCTAssertFalse(
            FeatureFlags.appleWorkoutParserTestModeEnabled(environment: [
                "WHOOPS_TEST_WORKOUT_MODEL": "live"
            ]))
        for mode in ["fixture", "slow", "unavailable"] {
            #if DEBUG && targetEnvironment(simulator)
                XCTAssertTrue(
                    FeatureFlags.appleWorkoutParserTestModeEnabled(environment: [
                        "WHOOPS_TEST_WORKOUT_MODEL": mode
                    ]))
            #else
                XCTAssertFalse(
                    FeatureFlags.appleWorkoutParserTestModeEnabled(environment: [
                        "WHOOPS_TEST_WORKOUT_MODEL": mode
                    ]))
            #endif
        }
    }

    private let source = """
        Complete as many rounds as possible in 8 minutes
        •4 Burpees
        •12 Overhead Kettlebell Swings (35#)
        Score: 5 rounds, 3 reps
        """

    private var extraction: WorkoutExtraction {
        WorkoutExtraction(
            format: "amrap", timeCap: "8 minutes",
            segments: [
                .init(
                    kind: "work", duration: "8 minutes", contextLines: [1],
                    movements: [
                        .init(line: 2, name: "Burpees", reps: "4"),
                        .init(line: 3, name: "Overhead Kettlebell Swings", reps: "12", load: "35#"),
                    ])
            ])
    }

    func testGroundedAMRAPAndScoreSeparation() async throws {
        let model = TestWorkoutModel(data: try JSONEncoder().encode(extraction))
        let result = try await OnDeviceWorkoutParser(model: model).parse(rawText: source)
        XCTAssertEqual(result.rawText, source)
        XCTAssertEqual(result.format, .amrap)
        XCTAssertEqual(result.timeCapSeconds, 480)
        XCTAssertNil(result.segments[0].rounds)
        XCTAssertEqual(result.movementsForTest.map(\.repetitions), [4, 12])
        XCTAssertEqual(result.movementsForTest[1].loadValue, 35)
        XCTAssertEqual(result.movementsForTest[1].loadUnit, "lb")
        XCTAssertEqual(result.movementsForTest[1].canonicalMovementID, "overhead_kettlebell_swing")
        XCTAssertTrue(
            result.segments[0].notes.contains("Reported result (not a prescription): Score:"))
        XCTAssertTrue(result.ambiguities.isEmpty)
        XCTAssertEqual(result.modelVersion, "synthetic-test-model")
        let prompt = await model.lastPrompt
        XCTAssertFalse(prompt?.contains("Score:") ?? true)
    }

    func testInventedQuantityAndScoreAsRoundsAreRejected() async throws {
        var fabricated = extraction
        fabricated.segments[0].movements[1].load = "44#"
        await assertRejected(fabricated)
        fabricated = extraction
        fabricated.segments[0].rounds = "5 rounds"
        await assertRejected(fabricated)
        fabricated = extraction
        fabricated.segments[0].movements[0].reps = "2"  // Must not match the 2 inside 12.
        await assertRejected(fabricated)
        fabricated = extraction
        fabricated.segments[0].rounds = "4"  // A rep count cannot silently become rounds.
        await assertRejected(fabricated)
    }

    func testLiteralNullSentinelsAreNormalizedWithoutAcceptingBadNumbers() async throws {
        var draft = extraction
        draft.segments[0].rounds = "null"
        draft.segments[0].rest = "null"
        draft.segments[0].movements[0].load = "null"
        let model = TestWorkoutModel(data: try JSONEncoder().encode(draft))
        let result = try await OnDeviceWorkoutParser(model: model).parse(rawText: source)
        XCTAssertNil(result.segments[0].rounds)
        XCTAssertNil(result.movementsForTest[0].loadValue)
        draft.segments[0].movements[0].reps = "NaN"
        await assertRejected(draft)
    }

    func testRestCannotBeInventedFromAnAMRAPDuration() async throws {
        var draft = extraction
        draft.segments.append(
            .init(kind: "rest", duration: "8 minutes", contextLines: [1], movements: []))
        await assertRejected(draft)
    }

    func testInvalidSourceReferencesAndDuplicateMovementsAreRejected() async throws {
        var invalid = extraction
        invalid.segments[0].movements[0].line = 4  // A result line is not a prescription.
        await assertRejected(invalid)
        invalid.segments[0].movements[0].line = 100
        await assertRejected(invalid)
        invalid = extraction
        invalid.segments[0].movements.append(invalid.segments[0].movements[0])
        await assertRejected(invalid)
    }

    func testUnknownNamesStayUnmappedAndMissingNumbersStayVisible() async throws {
        var draft = extraction
        draft.segments[0].movements[1].load = nil
        let model = TestWorkoutModel(data: try JSONEncoder().encode(draft))
        let result = try await OnDeviceWorkoutParser(model: model).parse(rawText: source)
        XCTAssertTrue(result.ambiguities.contains { $0.message.contains("Some source numbers") })
        let unknown = WorkoutExtraction(
            format: "manual",
            segments: [
                .init(
                    kind: "work", contextLines: [],
                    movements: [.init(line: 1, name: "Moon hops", reps: "6")])
            ])
        let unknownModel = TestWorkoutModel(data: try JSONEncoder().encode(unknown))
        let parsed = try await OnDeviceWorkoutParser(model: unknownModel).parse(
            rawText: "6 Moon hops")
        XCTAssertNil(parsed.movementsForTest[0].canonicalMovementID)
        XCTAssertTrue(parsed.ambiguities.contains { $0.message.contains("Unmapped") })
    }

    func testOmittedMovementCannotBeHiddenInContext() async throws {
        var draft = extraction
        draft.segments[0].movements.removeLast()
        draft.segments[0].contextLines.append(3)
        let model = TestWorkoutModel(data: try JSONEncoder().encode(draft))
        let result = try await OnDeviceWorkoutParser(model: model).parse(rawText: source)
        XCTAssertTrue(result.ambiguities.contains { $0.line == 3 })
    }

    func testUnitsConvertedInCodeAndRestStructureValidated() async throws {
        let source = "3 rounds\n0.5 km Row\nRest 1:30\n10 Strict Press (20 kg)"
        let draft = WorkoutExtraction(
            format: "rounds",
            segments: [
                .init(
                    kind: "work", rounds: "3 rounds", contextLines: [1],
                    movements: [
                        .init(line: 2, name: "Row", distance: "0.5 km")
                    ]),
                .init(kind: "rest", duration: "1:30", contextLines: [3], movements: []),
                .init(
                    kind: "work", contextLines: [],
                    movements: [
                        .init(line: 4, name: "Strict Press", reps: "10", load: "20 kg")
                    ]),
            ])
        let result = try await OnDeviceWorkoutParser(
            model: TestWorkoutModel(data: try JSONEncoder().encode(draft))
        ).parse(rawText: source)
        XCTAssertEqual(result.movementsForTest[0].distanceMeters, 500)
        XCTAssertEqual(result.segments[1].durationSeconds, 90)
        XCTAssertEqual(result.movementsForTest[1].loadUnit, "kg")
        var invalid = extraction
        invalid.segments[0].kind = "rest"
        await assertRejected(invalid)
    }

    func testUnavailableAndInvalidOutputUseVisibleDeterministicFallback() async throws {
        for model in [
            TestWorkoutModel(failure: .notReady), TestWorkoutModel(data: Data("{}".utf8)),
        ] {
            let parser = LibraryWorkoutParser(
                library: PreviewMovementLibraryRepository(), model: model)
            let result = try await parser.parse(rawText: source)
            XCTAssertEqual(result.parserVersion, VersionedWorkoutParser.parserVersion)
            XCTAssertNil(result.modelVersion)
            XCTAssertEqual(result.ambiguities.first?.id, "apple-parser-fallback")
            XCTAssertEqual(result.movementsForTest.count, 2)
        }
    }

    func testDisabledAndLongInputNeverCallModel() async throws {
        let model = TestWorkoutModel()
        let parser = LibraryWorkoutParser(
            library: PreviewMovementLibraryRepository(), model: model,
            isAIEnabled: { false })
        _ = try await parser.parse(rawText: source)
        let count = await model.calls
        XCTAssertEqual(count, 0)
        do {
            _ = try await OnDeviceWorkoutParser(model: model).parse(
                rawText: String(repeating: "8 Burpees\n", count: 400))
            XCTFail("Expected input limit")
        } catch WorkoutAIFailure.tooLong {}
        let finalCount = await model.calls
        XCTAssertEqual(finalCount, 0)
    }

    func testDroppedSourceQuantitiesUseFallbackInsteadOfDegradedAIDraft() async throws {
        var draft = extraction
        draft.segments[0].movements[1].load = nil
        let parser = LibraryWorkoutParser(
            library: PreviewMovementLibraryRepository(),
            model: TestWorkoutModel(data: try JSONEncoder().encode(draft)))
        let parsed = try await parser.parse(rawText: source)
        XCTAssertEqual(parsed.parserVersion, VersionedWorkoutParser.parserVersion)
        XCTAssertEqual(parsed.movementsForTest[1].loadValue, 35)
        XCTAssertEqual(parsed.ambiguities.first?.id, "apple-parser-fallback")
    }

    func testTimeoutReturnsFallbackWithoutWaitingForUncooperativeProvider() async throws {
        let model = TestWorkoutModel(delay: .milliseconds(500), ignoresCancellation: true)
        let parser = LibraryWorkoutParser(
            library: PreviewMovementLibraryRepository(), model: model,
            timeout: .milliseconds(10))
        let start = ContinuousClock.now
        let result = try await parser.parse(rawText: source)
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(400))
        XCTAssertTrue(result.ambiguities[0].message.contains("too long"))
    }

    func testCancellationDoesNotCreateFallbackDraft() async throws {
        let model = TestWorkoutModel(delay: .seconds(1))
        let parser = LibraryWorkoutParser(library: PreviewMovementLibraryRepository(), model: model)
        let source = source
        let task = Task { try await parser.parse(rawText: source) }
        while await model.calls == 0 { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled parse must not return a draft")
        } catch is CancellationError {}
    }

    private func assertRejected(_ draft: WorkoutExtraction) async {
        do {
            let model = TestWorkoutModel(data: try JSONEncoder().encode(draft))
            _ = try await OnDeviceWorkoutParser(model: model).parse(rawText: source)
            XCTFail("Expected invalid output to be rejected")
        } catch WorkoutAIFailure.invalidOutput {} catch { XCTFail("Unexpected error: \(error)") }
    }

    func testStagedPartsAreIsolatedOrderedAndAssembledWithCodeOwnedQuantities() async throws {
        let parts = TestPartModel([
            .init(role: "instruction", format: "amrap"),
            .init(role: "movement", format: "unspecified"),
            .init(role: "movement", format: "unspecified"),
        ])
        let result = try await OnDeviceWorkoutParser(model: TestStagedModel(parts: parts)).parse(
            rawText: source)
        XCTAssertEqual(result.format, .amrap)
        XCTAssertEqual(result.timeCapSeconds, 480)
        XCTAssertNil(result.segments[0].rounds)
        XCTAssertEqual(result.movementsForTest.map(\.repetitions), [4, 12])
        XCTAssertEqual(result.movementsForTest[1].loadValue, 35)
        XCTAssertTrue(result.ambiguities.isEmpty)
        let prompts = await parts.prompts
        XCTAssertEqual(prompts, Array(source.components(separatedBy: .newlines).prefix(3)))
        XCTAssertFalse(prompts.contains { $0.contains("\n") || $0.contains("Score:") })
        XCTAssertTrue(result.segments[0].notes.contains("Reported result"))
    }

    func testExplicitPartLabelsHaveFixedFieldMappings() throws {
        for (kind, role, format) in [
            ("exercise_line", "movement", "unspecified"),
            ("for_time_header", "instruction", "for_time"),
            ("amrap_header", "instruction", "amrap"),
            ("emom_header", "instruction", "emom"),
            ("round_count_header", "instruction", "rounds"),
            ("set_count_header", "instruction", "strength"),
            ("strength_header", "instruction", "strength"),
            ("time_cap_line", "instruction", "unspecified"),
            ("rest_line", "rest", "unspecified"),
            ("context_line", "context", "unspecified"),
        ] {
            let part = try WorkoutPartExtraction.classified(as: kind)
            XCTAssertEqual(part.role, role)
            XCTAssertEqual(part.format, format)
        }
        XCTAssertThrowsError(try WorkoutPartExtraction.classified(as: "invented_label"))
    }

    func testStagedSourceIDsSurviveBlankAndResultLines() async throws {
        let raw = "For time\n\n400 m Row\nScore: 7:30\n\n8 Burpees\nTime cap: 12 minutes"
        let parts = TestPartModel([
            .init(role: "instruction", format: "for_time"),
            .init(role: "movement", format: "unspecified"),
            .init(role: "movement", format: "unspecified"),
            .init(role: "instruction", format: "unspecified"),
        ])
        let result = try await OnDeviceWorkoutParser(model: TestStagedModel(parts: parts)).parse(
            rawText: raw)
        XCTAssertEqual(result.timeCapSeconds, 720)
        XCTAssertNil(result.segments[0].durationSeconds)
        XCTAssertEqual(result.movementsForTest.map(\.originalText), ["400 m Row", "8 Burpees"])
        XCTAssertTrue(result.ambiguities.isEmpty)
    }

    func testStagedRestAndStrengthAssembly() async throws {
        let rest = TestPartModel([
            .init(role: "instruction", format: "for_time"),
            .init(role: "movement", format: "unspecified"),
            .init(role: "rest", format: "unspecified"),
            .init(role: "movement", format: "unspecified"),
        ])
        let result = try await OnDeviceWorkoutParser(model: TestStagedModel(parts: rest)).parse(
            rawText: "For time\n0.5 km Row\nRest 1:30\n10 Burpees")
        XCTAssertEqual(result.segments.map(\.type), [.work, .rest, .work])
        XCTAssertEqual(result.segments[1].durationSeconds, 90)
        XCTAssertEqual(result.movementsForTest[0].distanceMeters, 500)
        let strength = TestPartModel([
            .init(role: "instruction", format: "strength"),
            .init(role: "instruction", format: "strength"),
            .init(role: "movement", format: "unspecified"),
        ])
        let sets = try await OnDeviceWorkoutParser(model: TestStagedModel(parts: strength)).parse(
            rawText: "Strength\n4 sets\n5 Deadlift at 70% 1RM")
        XCTAssertEqual(sets.segments[0].rounds, 4)
        XCTAssertEqual(sets.movementsForTest[0].repetitions, 5)
        XCTAssertEqual(sets.movementsForTest[0].percentageOfOneRepMax, 70)
        XCTAssertTrue(sets.ambiguities.isEmpty)
    }

    func testStagedFailureDiscardsAllPartialPiecesAndFallsBack() async throws {
        let parts = TestPartModel(
            [
                .init(role: "instruction", format: "amrap"),
                .init(role: "movement", format: "unspecified"),
            ], failureAt: 2)
        let parser = LibraryWorkoutParser(
            library: PreviewMovementLibraryRepository(), model: TestStagedModel(parts: parts))
        let result = try await parser.parse(rawText: source)
        XCTAssertEqual(result.parserVersion, VersionedWorkoutParser.parserVersion)
        XCTAssertNil(result.modelVersion)
        XCTAssertEqual(result.movementsForTest.count, 2)
        XCTAssertEqual(result.ambiguities.first?.id, "apple-parser-fallback")
    }

    func testStagedMisclassificationCannotHideUnknownMovementOrCreateAnInstructionMovement()
        async throws
    {
        for (raw, outputs) in [
            (
                "For time\n8 Burpees",
                [WorkoutPartExtraction(role: "movement", format: "unspecified")]
            ),
            ("6 Moon hops\n8 Burpees", [.init(role: "context", format: "unspecified")]),
            (
                "8 Burpees\n3 rounds\n10 Burpees",
                [
                    .init(role: "movement", format: "unspecified"),
                    .init(role: "instruction", format: "rounds"),
                ]
            ),
        ] {
            let parser = LibraryWorkoutParser(
                library: PreviewMovementLibraryRepository(),
                model: TestStagedModel(parts: TestPartModel(outputs)))
            let result = try await parser.parse(rawText: raw)
            XCTAssertEqual(result.parserVersion, VersionedWorkoutParser.parserVersion, raw)
            XCTAssertEqual(result.ambiguities.first?.id, "apple-parser-fallback", raw)
        }
    }

    func testStagedPartLimitIsCheckedBeforeAnyInference() async throws {
        let parts = TestPartModel([])
        do {
            _ = try await OnDeviceWorkoutParser(model: TestStagedModel(parts: parts)).parse(
                rawText: Array(
                    repeating: "8 Burpees", count: StagedWorkoutExtractor.maximumParts + 1
                ).joined(separator: "\n"))
            XCTFail("Expected bounded part count")
        } catch WorkoutAIFailure.tooLong {}
        let prompts = await parts.prompts
        XCTAssertTrue(prompts.isEmpty)
    }

    func testStagedCancellationStopsBeforeTheNextPartWithoutFallback() async throws {
        let parts = TestPartModel(
            [
                .init(role: "instruction", format: "amrap"),
                .init(role: "movement", format: "unspecified"),
                .init(role: "movement", format: "unspecified"),
            ], delayAt: 1)
        let raw = source
        let task = Task {
            try await LibraryWorkoutParser(
                library: PreviewMovementLibraryRepository(), model: TestStagedModel(parts: parts)
            ).parse(rawText: raw)
        }
        while await parts.prompts.count < 2 { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled work must not create a draft")
        } catch is CancellationError {}
        let prompts = await parts.prompts
        XCTAssertEqual(prompts.count, 2)
    }
}

private struct TestStagedModel: WorkoutTextGenerating {
    let modelIdentifier = "synthetic-staged-model"
    let parts: TestPartModel
    func generate(workout: String) async throws -> Data {
        try await StagedWorkoutExtractor(model: parts).generate(workout: workout)
    }
}

private actor TestPartModel: WorkoutPartGenerating {
    let outputs: [WorkoutPartExtraction]
    let failureAt: Int?
    let delayAt: Int?
    var prompts: [String] = []

    init(_ outputs: [WorkoutPartExtraction], failureAt: Int? = nil, delayAt: Int? = nil) {
        self.outputs = outputs
        self.failureAt = failureAt
        self.delayAt = delayAt
    }

    func generate(part: String) async throws -> WorkoutPartExtraction {
        let index = prompts.count
        prompts.append(part)
        if index == delayAt { try await Task.sleep(for: .seconds(2)) }
        if index == failureAt { throw WorkoutAIFailure.generationFailed }
        guard outputs.indices.contains(index) else { throw WorkoutAIFailure.invalidOutput }
        return outputs[index]
    }
}

private actor TestWorkoutModel: WorkoutTextGenerating {
    nonisolated let modelIdentifier = "synthetic-test-model"
    let data: Data
    let failure: WorkoutAIFailure?
    let delay: Duration
    let ignoresCancellation: Bool
    var lastPrompt: String?
    var calls = 0

    init(
        data: Data = Data(), failure: WorkoutAIFailure? = nil, delay: Duration = .zero,
        ignoresCancellation: Bool = false
    ) {
        self.data = data
        self.failure = failure
        self.delay = delay
        self.ignoresCancellation = ignoresCancellation
    }

    func generate(workout: String) async throws -> Data {
        calls += 1
        lastPrompt = workout
        if ignoresCancellation {
            await Task.detached { try? await Task.sleep(for: self.delay) }.value
        } else {
            try await Task.sleep(for: delay)
        }
        if let failure { throw failure }
        return data
    }
}

extension ParsedWorkout {
    fileprivate var movementsForTest: [MovementPrescription] { segments.flatMap(\.movements) }
}
