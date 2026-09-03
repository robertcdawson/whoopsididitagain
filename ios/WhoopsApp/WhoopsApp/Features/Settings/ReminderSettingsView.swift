import SwiftUI
import UIKit

struct ReminderSettingsView: View {
    let repository: any AssessmentRepository
    let reminderService: LocalReminderService

    @State private var settings = SleepScheduleSettings.standard
    @State private var preferences = ReminderPreferences.disabled
    @State private var authorizationStatus = ReminderAuthorizationStatus.notDetermined
    @State private var changingKinds = Set<ReminderKind>()
    @State private var errorMessage: String?

    init(
        repository: any AssessmentRepository,
        reminderService: LocalReminderService = .live()
    ) {
        self.repository = repository
        self.reminderService = reminderService
    }

    var body: some View {
        JournalForm {
            Section("Morning") {
                Toggle(
                    "Morning check-in reminder",
                    isOn: enabledBinding(for: .morningCheckIn)
                )
                .disabled(changingKinds.contains(.morningCheckIn))
                .accessibilityIdentifier("morning-reminder-toggle")
                LabeledContent(
                    "Time",
                    value: formattedTime(for: .morningCheckIn)
                )
                Text("Open goes directly to the check-in. Later reminds you again in 15 minutes.")
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            Section("Evening") {
                Toggle(
                    "Wind-down reminder",
                    isOn: enabledBinding(for: .windDown)
                )
                .disabled(changingKinds.contains(.windDown))
                .accessibilityIdentifier("wind-down-reminder-toggle")
                LabeledContent(
                    "Time",
                    value: formattedTime(for: .windDown)
                )
                Text(
                    "Done marks only today’s wind-down item complete. Later reminds you again in 15 minutes."
                )
                .font(.journal(.caption))
                .foregroundStyle(Color.journalInk.opacity(0.7))
            }

            Section {
                LabeledContent("iPhone notifications", value: authorizationDescription)
                if authorizationStatus == .denied {
                    Link(
                        "Open iPhone Settings",
                        destination: URL(string: UIApplication.openSettingsURLString)!
                    )
                    .accessibilityIdentifier("open-notification-settings")
                }
            } header: {
                Text("Permission")
            } footer: {
                Text(
                    "Both reminders are off until you turn them on. Times follow your saved sleep schedule; no health data leaves this phone."
                )
            }
        }
        .navigationTitle("Reminders")
        .task { await load() }
        .alert("Couldn’t update reminders", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func enabledBinding(for kind: ReminderKind) -> Binding<Bool> {
        Binding(
            get: { preferences.isEnabled(kind) },
            set: { enabled in
                preferences.setEnabled(enabled, for: kind)
                Task { await setEnabled(enabled, for: kind) }
            }
        )
    }

    private var authorizationDescription: String {
        switch authorizationStatus {
        case .notDetermined: "Not requested"
        case .denied: "Disabled"
        case .allowed: "Allowed"
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @MainActor
    private func load() async {
        do {
            settings = try await repository.sleepSettings()
            await reminderService.refreshEnabledSchedules(settings: settings)
            (preferences, authorizationStatus) = await reminderService.state()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func setEnabled(_ enabled: Bool, for kind: ReminderKind) async {
        changingKinds.insert(kind)
        defer { changingKinds.remove(kind) }
        do {
            try await reminderService.setEnabled(enabled, for: kind, settings: settings)
        } catch {
            preferences.setEnabled(!enabled, for: kind)
            errorMessage = error.localizedDescription
        }
        (preferences, authorizationStatus) = await reminderService.state()
    }

    private func formattedTime(for kind: ReminderKind) -> String {
        let reminder = ReminderScheduleFactory.dailyReminder(for: kind, settings: settings)
        let calendar = Calendar.autoupdatingCurrent
        let date =
            calendar.date(
                from: DateComponents(hour: reminder.hour, minute: reminder.minute)
            ) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        ReminderSettingsView(repository: PreviewAssessmentRepository())
    }
}
