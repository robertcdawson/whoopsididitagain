import SwiftUI

struct SleepScheduleSettingsView: View {
    let repository: any AssessmentRepository

    @State private var settings = SleepScheduleSettings.standard
    @State private var isSaving = false
    @State private var saved = false
    @State private var isConfirmingReset = false
    @State private var errorMessage: String?

    var body: some View {
        JournalForm {
            Section("Schedule") {
                DatePicker(
                    "Required wake time",
                    selection: wakeTime,
                    displayedComponents: .hourAndMinute
                )
                Stepper(
                    "Sleep target: \(Self.duration(settings.targetSleepMinutes))",
                    value: $settings.targetSleepMinutes,
                    in: 5 * 60...12 * 60,
                    step: 15
                )
                Stepper(
                    "Sleep latency: \(settings.sleepLatencyMinutes) min",
                    value: $settings.sleepLatencyMinutes,
                    in: 0...120,
                    step: 5
                )
                Stepper(
                    "Wind-down: \(settings.windDownMinutes) min",
                    value: $settings.windDownMinutes,
                    in: 0...120,
                    step: 5
                )
            }

            Section("Next deadline") {
                let deadline = SleepDeadlineCalculator.calculate(now: .now, settings: settings)
                LabeledContent(
                    "Begin wind-down",
                    value: deadline.windDownAt.formatted(date: .omitted, time: .shortened)
                )
                LabeledContent(
                    "Lights out",
                    value: deadline.lightsOutAt.formatted(date: .omitted, time: .shortened)
                )
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { ProgressView() } else { Text(saved ? "Saved" : "Save schedule") }
                }
                .disabled(isSaving)
                Button("Reset to default schedule", role: .destructive) {
                    isConfirmingReset = true
                }
                .disabled(isSaving)
            } footer: {
                Text(
                    "A schedule is needed to calculate your sleep deadline. Resetting removes your entries and restores the defaults."
                )
            }
        }
        .navigationTitle("Sleep Schedule")
        .task { await load() }
        .alert("Couldn’t save schedule", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .confirmationDialog(
            "Reset your sleep schedule?",
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset to defaults", role: .destructive) {
                Task { await reset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved times will be replaced by the default schedule.")
        }
    }

    private var wakeTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.wakeHour,
                    minute: settings.wakeMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.wakeHour = components.hour ?? settings.wakeHour
                settings.wakeMinute = components.minute ?? settings.wakeMinute
                saved = false
            }
        )
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.saveSleepSettings(settings)
            saved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func reset() async {
        settings = .standard
        await save()
    }

    private static func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }
}

#Preview {
    NavigationStack {
        SleepScheduleSettingsView(repository: PreviewAssessmentRepository())
    }
}
