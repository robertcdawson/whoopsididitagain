import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import WhoopsApp

final class FoundationBoundariesTests: XCTestCase {
    @MainActor
    func testJournalStatusTextAndInputBordersHaveReadablePaperContrast() {
        func components(_ color: Color) -> (rgb: [Double], alpha: Double) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            XCTAssertTrue(UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return ([Double(red), Double(green), Double(blue)], Double(alpha))
        }
        func luminance(_ rgb: [Double]) -> Double {
            let linear = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let paper = components(.journalPaper).rgb
        let paperLuminance = luminance(paper)
        let tokens: [(String, Color, Double)] = [
            ("positive text", .journalGreenText, 4.5),
            ("warning text", .journalAmberText, 4.5),
            ("error text", .journalRedPen, 4.5),
            ("secondary ink", .journalInk.opacity(0.7), 4.5),
            ("input border", .journalInk.opacity(0.55), 3),
            ("focused input border", .journalInk.opacity(0.9), 3),
        ]
        for (name, color, minimum) in tokens {
            let ink = components(color)
            let composite = zip(ink.rgb, paper).map { $0 * ink.alpha + $1 * (1 - ink.alpha) }
            let inkLuminance = luminance(composite)
            let contrast =
                (max(inkLuminance, paperLuminance) + 0.05)
                / (min(inkLuminance, paperLuminance) + 0.05)
            XCTAssertGreaterThanOrEqual(contrast, minimum, name)
        }
    }

    @MainActor
    func testJournalFontsAreBundledAndRegisteredForOfflineUse() throws {
        for name in ["Literata-Regular", "Literata-Italic", "Caveat-Regular"] {
            XCTAssertNotNil(UIFont(name: name, size: 19), "Missing journal font: \(name)")
        }
        for name in ["Literata", "Literata-Italic", "Caveat"] {
            XCTAssertNotNil(
                Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"))
        }
    }

    func testWorkoutParserPreservesOriginalText() async throws {
        let rawText = "3 rounds: 500 m row, 10 front squats"

        let result = try await VersionedWorkoutParser().parse(rawText: rawText)

        XCTAssertEqual(result.rawText, rawText)
        XCTAssertFalse(result.segments.isEmpty)
    }

    func testInMemoryStoreRoundTripsCodableValue() async throws {
        struct Example: Codable, Equatable, Sendable {
            let value: Int
        }

        let store = InMemoryLocalStore()
        try await store.save(Example(value: 42), forKey: "example")
        let loaded = try await store.load(Example.self, forKey: "example")

        XCTAssertEqual(loaded, Example(value: 42))
    }

    @MainActor
    func testWhoopPersistenceUpsertsSourceRecordsIdempotently() throws {
        let container = try ModelContainer(
            for: WhoopSourceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = WhoopPersistence(container: container)
        let response = WhoopSyncResponse(
            mode: .initial,
            startedAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 1_001),
            resources: [
                WhoopSyncResource(
                    resourceType: .recovery,
                    records: [
                        .object([
                            "cycle_id": .number(42),
                            "updated_at": .string("2026-08-15T12:00:00.000Z"),
                            "score": .object([
                                "recovery_score": .number(81),
                                "resting_heart_rate": .number(55),
                            ]),
                        ])
                    ],
                    pageCount: 1,
                    windowStart: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        _ = try persistence.upsert(response)
        _ = try persistence.upsert(response)
        let history = try persistence.history()

        XCTAssertEqual(history.recoveries.count, 1)
        XCTAssertEqual(history.recoveries.first?.recoveryScore, 81)
    }

    @MainActor
    func testWhoopSleepDurationUsesStageTotalsAndRoundsMinutes() throws {
        let container = try ModelContainer(
            for: WhoopSourceRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let persistence = WhoopPersistence(container: container)
        let minute = 60_000.0
        let response = WhoopSyncResponse(
            mode: .initial,
            startedAt: Date(timeIntervalSince1970: 1_000),
            completedAt: Date(timeIntervalSince1970: 1_001),
            resources: [
                WhoopSyncResource(
                    resourceType: .sleep,
                    records: [
                        .object([
                            "id": .number(42),
                            "start": .string("2026-08-26T22:00:00.000Z"),
                            "end": .string("2026-08-27T06:30:00.000Z"),
                            "nap": .bool(false),
                            "score": .object([
                                "stage_summary": .object([
                                    "total_in_bed_time_milli": .number(510 * minute),
                                    "total_awake_time_milli": .number(30 * minute),
                                    "total_no_data_time_milli": .number(60 * minute),
                                    "total_light_sleep_time_milli": .number(300.6 * minute),
                                    "total_slow_wave_sleep_time_milli": .number(60 * minute),
                                    "total_rem_sleep_time_milli": .number(60 * minute),
                                ])
                            ]),
                        ])
                    ],
                    pageCount: 1,
                    windowStart: Date(timeIntervalSince1970: 0)
                )
            ]
        )

        _ = try persistence.upsert(response)
        let sleep = try XCTUnwrap(persistence.history().sleeps.first)

        XCTAssertEqual(sleep.sleepMinutes, 421)
    }

    func testTodaySleepSelectionUsesPrimarySleepWakeDayAndIgnoresNaps() throws {
        let primary = SleepHistoryItem(
            id: "primary",
            start: date("2026-08-26T22:00:00Z"),
            end: date("2026-08-27T06:30:00Z"),
            isNap: false,
            sleepPerformance: 90,
            sleepMinutes: 480
        )
        let nap = SleepHistoryItem(
            id: "nap",
            start: date("2026-08-27T18:00:00Z"),
            end: date("2026-08-27T18:30:00Z"),
            isNap: true,
            sleepPerformance: nil,
            sleepMinutes: 30
        )

        let selected = TodaySleepSelector.primarySleep(
            for: "2026-08-27",
            in: [nap, primary],
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertEqual(selected, primary)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
