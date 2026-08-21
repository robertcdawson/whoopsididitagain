import XCTest

@testable import WhoopsApp

final class APIModelsTests: XCTestCase {
    func testHealthEnvelopeDecodesSharedContract() throws {
        let json = """
            {
              "data": {
                "status": "ok",
                "service": "whoops-backend",
                "version": "0.1.0",
                "timestamp": "2026-08-15T12:00:00Z"
              },
              "meta": { "requestId": "request-123" }
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(APIEnvelope<BackendHealth>.self, from: Data(json.utf8))

        XCTAssertEqual(envelope.data.status, "ok")
        XCTAssertEqual(envelope.data.service, "whoops-backend")
        XCTAssertEqual(envelope.meta.requestId, "request-123")
    }

    func testWhoopSyncEnvelopePreservesTypedAndRawSourceData() throws {
        let json = """
            {
              "data": {
                "mode": "initial",
                "startedAt": "2026-08-15T12:00:00Z",
                "completedAt": "2026-08-15T12:00:01Z",
                "resources": [{
                  "resourceType": "recovery",
                  "records": [{
                    "cycle_id": 123,
                    "score": { "recovery_score": 81 }
                  }],
                  "pageCount": 1,
                  "windowStart": "2026-02-16T12:00:00Z"
                }]
              },
              "meta": { "requestId": "request-sync" }
            }
            """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(
            APIEnvelope<WhoopSyncResponse>.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(envelope.data.mode, .initial)
        XCTAssertEqual(envelope.data.resources.first?.resourceType, .recovery)
        XCTAssertEqual(
            envelope.data.resources.first?.records.first?.objectValue?["cycle_id"]?.numberValue,
            123
        )
    }
}
