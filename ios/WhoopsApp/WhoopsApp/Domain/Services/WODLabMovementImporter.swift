import Foundation

enum WODLabMovementCategory: String, CaseIterable, Codable, Sendable {
    case weightlifting
    case power
    case gymnastics
    case machine
    case running
    case jumping
    case carry
    case oddObject = "odd_object"
    case crossfit
}

struct WODLabMovementImportCandidate: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let category: WODLabMovementCategory
    let aliases: [String]
}

struct WODLabMovementImportIssue: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case deletedRecord = "deleted_record"
        case invalidRecord = "invalid_record"
        case missingID = "missing_id"
        case missingName = "missing_name"
        case missingCategory = "missing_category"
        case unsupportedCategory = "unsupported_category"
        case invalidAliases = "invalid_aliases"
    }

    let recordIndex: Int
    let sourceID: String?
    let kind: Kind
    let message: String
}

struct WODLabMovementImportResult: Equatable, Sendable {
    let candidates: [WODLabMovementImportCandidate]
    let skippedCount: Int
    let issues: [WODLabMovementImportIssue]

    var importedCount: Int { candidates.count }
}

enum WODLabMovementImportError: Error, Equatable, LocalizedError, Sendable {
    case malformedJSON
    case invalidTopLevel
    case invalidVersion
    case unsupportedVersion(Int)
    case missingStores
    case missingMovementsStore
    case invalidMovementsStore

    var errorDescription: String? {
        switch self {
        case .malformedJSON:
            "The selected file is not valid JSON."
        case .invalidTopLevel:
            "The selected file is not a WOD Lab full export."
        case .invalidVersion:
            "The WOD Lab export is missing a valid version."
        case .unsupportedVersion(let version):
            "WOD Lab export version \(version) is not supported."
        case .missingStores:
            "The WOD Lab export is missing its stores object."
        case .missingMovementsStore:
            "The WOD Lab export does not contain a movements store."
        case .invalidMovementsStore:
            "The WOD Lab movements store is not an array."
        }
    }
}

/// Extracts only stable movement identity data from a WOD Lab version 1 full export.
/// Workout-specific prescriptions live in WOD Lab's `workout_movements` store and are
/// intentionally outside this importer's output model.
struct WODLabMovementImporter: Sendable {
    func importMovements(from data: Data) throws -> WODLabMovementImportResult {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WODLabMovementImportError.malformedJSON
        }

        guard let root = value as? [String: Any] else {
            throw WODLabMovementImportError.invalidTopLevel
        }
        guard let version = root["version"] as? Int else {
            throw WODLabMovementImportError.invalidVersion
        }
        guard version == 1 else {
            throw WODLabMovementImportError.unsupportedVersion(version)
        }
        guard let stores = root["stores"] as? [String: Any] else {
            throw WODLabMovementImportError.missingStores
        }
        guard let rawMovements = stores["movements"] else {
            throw WODLabMovementImportError.missingMovementsStore
        }
        guard let movements = rawMovements as? [Any] else {
            throw WODLabMovementImportError.invalidMovementsStore
        }

        var candidates: [WODLabMovementImportCandidate] = []
        var skippedCount = 0
        var issues: [WODLabMovementImportIssue] = []

        for (index, value) in movements.enumerated() {
            guard let record = value as? [String: Any] else {
                skippedCount += 1
                issues.append(
                    issue(
                        index: index,
                        id: nil,
                        kind: .invalidRecord,
                        message: "Movement record \(index + 1) is not an object."
                    )
                )
                continue
            }

            let rawID = trimmedString(record["id"])
            if record["deleted"] as? Bool == true {
                skippedCount += 1
                issues.append(
                    issue(
                        index: index,
                        id: rawID,
                        kind: .deletedRecord,
                        message: "Deleted movement was not imported."
                    )
                )
                continue
            }

            let name = trimmedString(record["name"])
            let rawCategory = trimmedString(record["category"])
            var validationIssues: [WODLabMovementImportIssue] = []

            if rawID == nil {
                validationIssues.append(
                    issue(
                        index: index,
                        id: nil,
                        kind: .missingID,
                        message: "Movement id must not be blank."
                    )
                )
            }
            if name == nil {
                validationIssues.append(
                    issue(
                        index: index,
                        id: rawID,
                        kind: .missingName,
                        message: "Movement name must not be blank."
                    )
                )
            }
            if rawCategory == nil {
                validationIssues.append(
                    issue(
                        index: index,
                        id: rawID,
                        kind: .missingCategory,
                        message: "Movement category must not be blank."
                    )
                )
            }

            let category = rawCategory.flatMap {
                WODLabMovementCategory(rawValue: $0.lowercased())
            }
            if let rawCategory, category == nil {
                validationIssues.append(
                    issue(
                        index: index,
                        id: rawID,
                        kind: .unsupportedCategory,
                        message: "Unsupported WOD Lab movement category: \(rawCategory)."
                    )
                )
            }

            guard
                validationIssues.isEmpty,
                let id = rawID,
                let name,
                let category
            else {
                skippedCount += 1
                issues.append(contentsOf: validationIssues)
                continue
            }

            let aliasResult = aliases(from: record["aliases"], excluding: name)
            if aliasResult.hadInvalidValues {
                issues.append(
                    issue(
                        index: index,
                        id: id,
                        kind: .invalidAliases,
                        message: "Invalid or blank aliases were ignored."
                    )
                )
            }
            candidates.append(
                WODLabMovementImportCandidate(
                    id: id,
                    name: name,
                    category: category,
                    aliases: aliasResult.values
                )
            )
        }

        return WODLabMovementImportResult(
            candidates: candidates,
            skippedCount: skippedCount,
            issues: issues
        )
    }

    private func issue(
        index: Int,
        id: String?,
        kind: WODLabMovementImportIssue.Kind,
        message: String
    ) -> WODLabMovementImportIssue {
        WODLabMovementImportIssue(
            recordIndex: index,
            sourceID: id,
            kind: kind,
            message: message
        )
    }

    private func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func aliases(from value: Any?, excluding name: String) -> (
        values: [String], hadInvalidValues: Bool
    ) {
        guard let value else { return ([], false) }

        let rawAliases: [Any]
        if let array = value as? [Any] {
            rawAliases = array
        } else if let alias = value as? String {
            rawAliases = [alias]
        } else {
            return ([], true)
        }

        var seen = Set([name.lowercased()])
        var aliases: [String] = []
        var hadInvalidValues = false
        for value in rawAliases {
            guard let alias = trimmedString(value) else {
                hadInvalidValues = true
                continue
            }
            let normalized = alias.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            aliases.append(alias)
        }
        return (aliases, hadInvalidValues)
    }
}
