import Foundation

// This standalone harness compiles the production parser/model files without the app or health
// repositories. Its only adapter is the same one-method parser protocol used by the app.
protocol WorkoutParser: Sendable {
    func parse(rawText: String) async throws -> ParsedWorkout
}

@main
struct EvaluateAppleWorkoutParser {
    struct Fixture: Decodable {
        let id: String
        let text: String
        let expected: Projection
        let requiresReview: Bool?
    }

    struct Projection: Codable, Equatable {
        let format: String
        let timeCap: Double?
        let segments: [Segment]

        struct Segment: Codable, Equatable {
            let kind: String
            let rounds: Int?
            let duration: Double?
            let rest: Double?
            let movements: [Movement]
        }
        struct Movement: Codable, Equatable {
            let id: String?
            let reps: Int?
            let distance: Int?
            let calories: Int?
            let load: Double?
            let unit: String?
            let duration: Double?
            let percentage: Double?
        }

        init(_ parsed: ParsedWorkout) {
            format = parsed.format.rawValue
            timeCap = parsed.timeCapSeconds
            segments = parsed.segments.map {
                Segment(
                    kind: $0.type.rawValue, rounds: $0.rounds, duration: $0.durationSeconds,
                    rest: $0.restSeconds,
                    movements: $0.movements.map {
                        Movement(
                            id: $0.canonicalMovementID, reps: $0.repetitions,
                            distance: $0.distanceMeters, calories: $0.calories,
                            load: $0.loadValue, unit: $0.loadUnit, duration: $0.durationSeconds,
                            percentage: $0.percentageOfOneRepMax)
                    })
            }
        }
    }

    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: evaluate-apple-parser.sh [--built-in] [--fresh] [fixture-id ...]")
            return
        }
        var fixtureURL = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.contains("--fresh") {
            fixtureURL = fixtureURL.deletingLastPathComponent().appendingPathComponent(
                "apple-parser-fresh.json")
        }
        let fixtures = try JSONDecoder().decode(
            [Fixture].self,
            from: Data(contentsOf: fixtureURL))
        let useBuiltIn = CommandLine.arguments.contains("--built-in")
        let fixtureIDs = CommandLine.arguments.dropFirst(2).filter {
            $0 != "--built-in" && $0 != "--fresh"
        }
        let selected =
            fixtureIDs.isEmpty ? fixtures : fixtures.filter { fixtureIDs.contains($0.id) }
        guard !selected.isEmpty else {
            print("No matching fixtures.")
            exit(1)
        }
        let model = EvaluationModel()
        let parser: any WorkoutParser =
            useBuiltIn ? VersionedWorkoutParser() : OnDeviceWorkoutParser(model: model)
        print("Model: \(useBuiltIn ? "none (built-in baseline)" : model.modelIdentifier)")
        let version =
            useBuiltIn ? VersionedWorkoutParser.parserVersion : OnDeviceWorkoutParser.parserVersion
        print(
            "Parser: \(version). Synthetic fixtures only. No fallback masking."
        )
        var passed = 0
        var rejected = 0
        var durations: [Double] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for fixture in selected {
            let start = ContinuousClock.now
            do {
                let result = try await parser.parse(rawText: fixture.text)
                let actual = Projection(result)
                let complete = !result.ambiguities.contains {
                    $0.id.hasPrefix("apple-parser-incomplete-")
                }
                let matches =
                    actual == fixture.expected && complete
                    && (fixture.requiresReview != true || !result.ambiguities.isEmpty)
                if matches { passed += 1 }
                print(
                    "\(matches ? "PASS" : "FAIL") \(fixture.id) \(start.duration(to: .now)) ambiguities=\(result.ambiguities.count)"
                )
                if !matches {
                    print(
                        "  actual: \(String(decoding: try encoder.encode(actual), as: UTF8.self))")
                    print(
                        "  expected: \(String(decoding: try encoder.encode(fixture.expected), as: UTF8.self))"
                    )
                }
            } catch {
                rejected += 1
                let failure = error as? WorkoutAIFailure
                print(
                    "UNAVAILABLE/FAIL \(fixture.id) \(start.duration(to: .now)): \(failure?.message ?? "Parser error")"
                )
                if case .invalidOutput? = failure, let data = await model.lastData {
                    print("  synthetic extraction: \(String(decoding: data, as: UTF8.self))")
                }
                if case .disabled? = failure { break }
                if case .notReady? = failure { break }
                if case .unsupported? = failure { break }
            }
            let duration = start.duration(to: .now).components
            durations.append(Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        }
        print("Exact structural matches: \(passed)/\(selected.count)")
        print("Rejected/unavailable (would need fallback): \(rejected)/\(selected.count)")
        let sorted = durations.sorted()
        if !sorted.isEmpty {
            let median = sorted[sorted.count / 2]
            let p95 = sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            print(
                String(
                    format:
                        "All-attempt latency: median %.3fs, p95 %.3fs, max %.3fs (includes early rejection; not phone performance)",
                    median, p95, sorted.last!))
        }
        if passed != selected.count { exit(1) }
    }
}

private actor EvaluationModel: WorkoutTextGenerating {
    nonisolated var modelIdentifier: String { AppleWorkoutModelClient().modelIdentifier }
    var lastData: Data?
    func generate(workout: String) async throws -> Data {
        lastData = nil
        let data = try await AppleWorkoutModelClient().generate(workout: workout)
        lastData = data
        return data
    }
}
