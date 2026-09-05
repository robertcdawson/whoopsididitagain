import SwiftUI
import UIKit

struct PTSummary: Equatable {
    struct Section: Equatable, Identifiable {
        var title: String
        var lines: [String]
        var id: String { title }
    }
    var start: Date
    var end: Date
    var sections: [Section]
}

/// The same dated, descriptive material drives preview and PDF; no historical denominator
/// is reconstructed from a protocol's current recurrence.
enum PTSummaryBuilder {
    static func build(
        start: Date, end: Date, calendar: Calendar = .autoupdatingCurrent,
        restrictions: [RestrictionProfile], protocols: [TherapyProtocol],
        completions: [DocketCompletion], workouts: [CompletedWorkout], pain: [PainLogEntry],
        questions: String
    ) -> PTSummary {
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!
        func included(_ date: Date) -> Bool { date >= lower && date < upper }
        func date(_ value: Date) -> String { value.formatted(date: .abbreviated, time: .shortened) }
        let items = protocols.flatMap(\.items)
        let selectedDays = Set(days(start: start, end: end, calendar: calendar))
        let recorded = completions.filter { completion in
            guard completion.kind == .protocolItem else { return false }
            return selectedDays.contains(completion.day)
        }.sorted { $0.completedAt < $1.completedAt }
        let logs = pain.filter { included($0.occurredAt) }.sorted { $0.occurredAt < $1.occurredAt }
        let training = workouts.filter { included($0.startedAt) }.sorted {
            $0.startedAt < $1.startedAt
        }
        let prescriptionLines = protocols.filter { !$0.isArchived }.sorted { $0.title < $1.title }
            .flatMap { value in
                [value.title + " · current prescription"]
                    + value.items.sorted { $0.order < $1.order }.map {
                        "\($0.displayName): \($0.prescriptionSummary ?? "Quantity not recorded") · \($0.cadence.displayName)"
                    }
            }
        let completionLines = recorded.map { value -> String in
            let name =
                items.first { $0.id == value.sourceID }?.displayName
                ?? "Protocol item (source no longer available)"
            guard let actual = value.actual else {
                return "\(value.day) · \(name): completed; quantities not recorded"
            }
            let quantity = [
                actual.sets.map { "\($0) sets" }, actual.repetitions.map { "\($0) reps" },
                actual.durationSeconds.map { "\($0) seconds" },
            ].compactMap { $0 }.joined(separator: ", ")
            let pain = actual.painDuring.map { "\($0)/10" } ?? "not recorded"
            return
                "\(value.day) · \(name): \(actual.isAsPrescribed ? "as prescribed" : "modified") · \(quantity) · pain \(pain)\(actual.note.isEmpty ? "" : " · " + actual.note)"
        }
        let workoutLines = training.flatMap { value in
            [
                "\(date(value.startedAt)) · \(value.title) · RPE \(value.sessionRPE)/10 · post-session pain \(value.postSessionPain)/10"
            ]
                + value.movements.filter {
                    !$0.modification.isEmpty || $0.reportedPain != nil || !$0.notes.isEmpty
                }.map {
                    "\($0.displayName) · pain \($0.reportedPain.map { "\($0)/10" } ?? "not recorded")\($0.modification.isEmpty ? "" : " · " + $0.modification)\($0.notes.isEmpty ? "" : " · " + $0.notes)"
                } + (value.notes.isEmpty ? [] : [value.notes])
        }
        return PTSummary(
            start: lower, end: calendar.startOfDay(for: end),
            sections: [
                .init(
                    title: "About this summary",
                    lines: [
                        "Recorded observations for your PT discussion. Record dates do not describe healing milestones or medical clearance.",
                        "Prescriptions and restrictions below are current. Completion counts describe recorded work, not historical adherence. Missing entries do not establish that work was missed.",
                    ]),
                .init(
                    title: "Current restrictions",
                    lines: restrictions.filter(\.isActive).sorted { $0.injuryName < $1.injuryName }
                        .map {
                            "\($0.injuryName) · \($0.level.displayName) · \(MovementDemand(rawValue: $0.movementTag)?.displayName ?? $0.movementTag) · \($0.rationale)"
                        }),
                .init(title: "Current prescriptions", lines: prescriptionLines),
                .init(
                    title: "Protocol work · \(recorded.count) recorded completions",
                    lines: completionLines),
                .init(title: "Workouts · \(training.count) recorded sessions", lines: workoutLines),
                .init(
                    title: "Pain log · \(logs.count) entries",
                    lines: logs.map { value in
                        let area =
                            BodyAreaCatalog.definitions(for: [value.bodyAreaID]).first?.label
                            ?? value.bodyAreaID
                        return
                            "\(date(value.occurredAt)) · \(area) · \(value.intensity)/10\(value.note.isEmpty ? "" : " · " + value.note)"
                    }),
                .init(
                    title: "Questions for PT",
                    lines: questions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? [] : [questions]),
            ])
    }

    static func days(start: Date, end: Date, calendar: Calendar = .autoupdatingCurrent) -> [String]
    {
        var result: [String] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
            result.append(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor
            else { break }
            cursor = next
        }
        return result
    }
}

@MainActor
enum PTSummaryPDF {
    static func data(_ summary: PTSummary) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var y: CGFloat = 0
            func beginPage() {
                context.beginPage()
                y = 44
                ("WHOOPs · Bring to PT" as NSString).draw(
                    at: CGPoint(x: 44, y: y),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 18)])
                y += 30
                let dates =
                    summary.start.formatted(date: .abbreviated, time: .omitted) + " – "
                    + summary.end.formatted(date: .abbreviated, time: .omitted)
                (dates as NSString).draw(
                    at: CGPoint(x: 44, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
                )
                y += 26
            }
            func draw(_ text: String, heading: Bool = false) {
                let font =
                    heading ? UIFont.boldSystemFont(ofSize: 14) : UIFont.systemFont(ofSize: 11)
                // TextKit lays out fragments, so a single long note can span multiple pages.
                let storage = NSTextStorage(
                    string: text, attributes: [.font: font, .foregroundColor: UIColor.black])
                let layout = NSLayoutManager()
                storage.addLayoutManager(layout)
                let container = NSTextContainer(
                    size: CGSize(width: 524, height: CGFloat.greatestFiniteMagnitude))
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                layout.ensureLayout(for: container)
                layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) {
                    rect, _, _, range, _ in
                    if y + rect.height > 744 { beginPage() }
                    layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: 44, y: y - rect.minY))
                    y += rect.height
                }
                y += heading ? 8 : 10
            }
            beginPage()
            for section in summary.sections {
                if y > 690 { beginPage() }
                draw(section.title, heading: true)
                for line in section.lines.isEmpty
                    ? ["Not recorded for this summary."] : section.lines
                { draw(line) }
                y += 8
            }
        }
    }
}

struct PTSummaryView: View {
    let assessmentRepository: any AssessmentRepository
    let workoutRepository: any WorkoutRepository
    let protocolRepository: any ProtocolRepository
    let docketRepository: any DocketRepository
    @FocusState private var focusedField: UUID?
    @State private var days = 14
    @State private var start = Calendar.autoupdatingCurrent.date(
        byAdding: .day, value: -13, to: .now)!
    @State private var end = Date.now
    @State private var questions = ""
    @State private var summary: PTSummary?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var loadID = UUID()
    @State private var pdfURL: URL?
    @State private var restrictions: [RestrictionProfile] = []
    @State private var protocols: [TherapyProtocol] = []
    @State private var completions: [DocketCompletion] = []
    @State private var workouts: [CompletedWorkout] = []
    @State private var pain: [PainLogEntry] = []

    var body: some View {
        JournalForm {
            Section("Dates") {
                Picker("Period", selection: $days) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("Custom").tag(0)
                }
                if days == 0 {
                    DatePicker("From", selection: $start, in: ...end, displayedComponents: .date)
                    DatePicker(
                        "Through", selection: $end, in: start...Date.now, displayedComponents: .date
                    )
                }
            }
            Section("Questions for PT") {
                TextField("What would you like to discuss?", text: $questions, axis: .vertical)
                    .formKeyboardField(dismissOnSubmit: false).dictationInput($questions)
            }
            if isLoading { ProgressView("Preparing summary…") }
            if let summary {
                ForEach(summary.sections.filter { $0.title != "Questions for PT" }) { section in
                    Section(section.title) {
                        ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                        }
                        if section.lines.isEmpty {
                            Text("Not recorded for this summary.").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bring to PT")
        .formKeyboardScope($focusedField)
        .recoverableDraft(key: "pt-questions:current", value: $questions)
        .journalSaveBar {
            if let pdfURL {
                ShareLink("Share PDF", item: pdfURL).accessibilityIdentifier("share-pt-pdf")
            } else {
                Button("Prepare PDF") { export() }.disabled(summary == nil || isLoading)
                    .accessibilityIdentifier("prepare-pt-pdf")
            }
        }
        .task(id: dateKey) { await load() }
        .onChange(of: days) { _, count in
            if count > 0 {
                end = .now
                start = Calendar.autoupdatingCurrent.date(
                    byAdding: .day, value: -(count - 1), to: end)!
            }
        }
        .onChange(of: questions) { _, _ in rebuild() }
        .onDisappear { removePDF() }
        .alert(
            "Couldn't prepare summary",
            isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("Retry") { Task { await load() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var dateKey: String { "\(start.timeIntervalSince1970):\(end.timeIntervalSince1970)" }
    @MainActor private func load() async {
        let requestID = UUID()
        loadID = requestID
        let requestStart = start
        let requestEnd = end
        isLoading = true
        hasLoaded = false
        summary = nil
        removePDF()
        defer { if loadID == requestID { isLoading = false } }
        do {
            let loadedRestrictions = try await assessmentRepository.restrictions()
            let loadedProtocols = try await protocolRepository.protocols(includeArchived: true)
            let loadedCompletions = try await docketRepository.completions(
                days: PTSummaryBuilder.days(start: requestStart, end: requestEnd))
            let loadedWorkouts = try await workoutRepository.completedWorkouts()
            let loadedPain = try await assessmentRepository.painLogs()
            try Task.checkCancellation()
            guard loadID == requestID, start == requestStart, end == requestEnd else { return }
            restrictions = loadedRestrictions
            protocols = loadedProtocols
            completions = loadedCompletions
            workouts = loadedWorkouts
            pain = loadedPain
            hasLoaded = true
            errorMessage = nil
            rebuild()
        } catch is CancellationError {} catch {
            if loadID == requestID { errorMessage = error.localizedDescription }
        }
    }
    private func rebuild() {
        removePDF()
        guard hasLoaded else {
            summary = nil
            return
        }
        summary = PTSummaryBuilder.build(
            start: start, end: end, restrictions: restrictions, protocols: protocols,
            completions: completions, workouts: workouts, pain: pain, questions: questions)
    }
    private func export() {
        guard let summary else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                "Bring-to-PT-\(UUID().uuidString).pdf")
            try PTSummaryPDF.data(summary).write(
                to: url, options: [.atomic, .completeFileProtection])
            pdfURL = url
        } catch { errorMessage = error.localizedDescription }
    }
    private func removePDF() {
        if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
        pdfURL = nil
    }
}
