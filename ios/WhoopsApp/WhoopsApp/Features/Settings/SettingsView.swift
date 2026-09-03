import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("journalLeftHanded") private var leftHanded = false
    @StateObject private var whoop: WhoopConnectionModel
    @StateObject private var healthKit: HealthKitConnectionModel
    @AppStorage(FeatureFlags.experimentLabKey) private var experimentLabEnabled = false
    let assessmentRepository: any AssessmentRepository
    let reminderService: LocalReminderService

    init(
        whoopRepository: any WhoopRepository,
        healthKitRepository: any HealthKitRepository,
        assessmentRepository: any AssessmentRepository,
        reminderService: LocalReminderService = .live()
    ) {
        _whoop = StateObject(wrappedValue: WhoopConnectionModel(repository: whoopRepository))
        _healthKit = StateObject(
            wrappedValue: HealthKitConnectionModel(repository: healthKitRepository)
        )
        self.assessmentRepository = assessmentRepository
        self.reminderService = reminderService
    }

    var body: some View {
        NavigationStack {
            JournalList {
                Section("Body & restrictions") {
                    NavigationLink {
                        RestrictionManagementView(repository: assessmentRepository)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Restrictions", systemImage: "bandage")
                            Text("Injuries, affected areas, and movement limits")
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                    }
                    .accessibilityIdentifier("settings-restrictions")
                }

                Section("Connections") {
                    HStack {
                        Label("WHOOP", systemImage: "heart.circle")
                        Spacer()
                        Text(whoop.status.connected ? "Connected" : "Not connected")
                            .foregroundStyle(
                                whoop.status.connected
                                    ? Color.journalGreenText : .journalInk.opacity(0.7))
                    }

                    if whoop.status.connected {
                        if let userID = whoop.status.whoopUserId {
                            LabeledContent("WHOOP user", value: userID)
                        }
                        Toggle(
                            "Delete local WHOOP history",
                            isOn: $whoop.deleteLocalHistoryOnDisconnect
                        )
                        Button("Disconnect WHOOP", role: .destructive) {
                            Task { await whoop.disconnect() }
                        }
                        .disabled(whoop.isWorking)
                    } else {
                        Button {
                            Task { await whoop.connect() }
                        } label: {
                            if whoop.isWorking {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text("Connect WHOOP")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(JournalPrimaryButtonStyle())
                        .disabled(whoop.isWorking)
                        .accessibilityIdentifier("connect-whoop")
                    }

                    HStack {
                        Label("Apple Health", systemImage: "heart.text.square")
                        Spacer()
                        Text(healthKit.statusText)
                            .foregroundStyle(
                                healthKit.authorizationState == .requested
                                    ? Color.journalGreenText : .journalInk.opacity(0.7)
                            )
                    }

                    if healthKit.authorizationState == .requested {
                        LabeledContent(
                            "Imported records",
                            value: healthKit.history.recordCount.formatted()
                        )
                        LabeledContent(
                            "Linked workouts",
                            value: healthKit.history.linkedWorkoutCount.formatted()
                        )
                        if let lastSyncAt = healthKit.history.lastSyncAt {
                            LabeledContent(
                                "Last Apple Health sync",
                                value: lastSyncAt.formatted(.relative(presentation: .named))
                            )
                        }
                        Button("Synchronize Apple Health") {
                            Task { await healthKit.synchronize() }
                        }
                        .disabled(healthKit.isWorking)
                        NavigationLink {
                            AppleHealthDataInclusionView(model: healthKit)
                        } label: {
                            Label("Included Apple Health data", systemImage: "checklist")
                        }
                    } else if healthKit.authorizationState == .notRequested {
                        Button("Allow Apple Health read access") {
                            Task { await healthKit.requestAccess() }
                        }
                        .disabled(healthKit.isWorking)
                        .accessibilityIdentifier("connect-apple-health")
                    }

                    Text(
                        "Read-only. Imported data depends on the Health categories you allowed; Apple does not reveal which read categories were denied."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                }

                if let errorMessage = whoop.errorMessage {
                    Section("Connection issue") {
                        Text(errorMessage)
                            .foregroundStyle(Color.journalRedPen)
                    }
                }

                if let errorMessage = healthKit.errorMessage {
                    Section("Apple Health issue") {
                        Text(errorMessage)
                            .foregroundStyle(Color.journalRedPen)
                    }
                }

                Section("Daily planning") {
                    NavigationLink {
                        SleepScheduleSettingsView(
                            repository: assessmentRepository,
                            reminderService: reminderService
                        )
                    } label: {
                        Label("Sleep schedule", systemImage: "bed.double")
                    }
                    NavigationLink {
                        ReminderSettingsView(
                            repository: assessmentRepository,
                            reminderService: reminderService
                        )
                    } label: {
                        Label("Reminders", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("settings-reminders")
                }

                Section("Journal") {
                    Toggle("Left-handed layout", isOn: $leftHanded)
                        .accessibilityIdentifier("journal-left-handed")
                    Text(
                        "Moves the notebook margin and Settings control to the other side. Text stays readable in its normal direction."
                    )
                    .font(.journal(.caption))
                }

                Section("Privacy") {
                    Label("Imported health data stays on this device", systemImage: "lock.shield")
                    Label("Export local data", systemImage: "square.and.arrow.up")
                        .foregroundStyle(Color.journalInk.opacity(0.7))
                }

                Section("Experimental features") {
                    Toggle("Personal Experiment Lab", isOn: $experimentLabEnabled)
                        .accessibilityIdentifier("experiment-lab-toggle")
                    Text(
                        "When enabled, Body can compare intervention and comparison days using locally stored outcomes. Results are exploratory and are not medical advice."
                    )
                    .font(.journal(.caption))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                }

                Section("About") {
                    LabeledContent("Foundation version", value: "0.8.0")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("close-settings")
                }
            }
            .task {
                await whoop.refresh()
                await healthKit.refresh()
            }
        }
    }
}

private struct AppleHealthDataInclusionView: View {
    @ObservedObject var model: HealthKitConnectionModel

    var body: some View {
        JournalList {
            Section {
                ForEach(HealthMetric.userSelectableMetrics) { metric in
                    Toggle(
                        isOn: Binding(
                            get: { model.isIncluded(metric) },
                            set: { model.setMetric(metric, included: $0) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.displayName)
                            Text(metric.inclusionDescription)
                                .font(.journal(.caption))
                                .foregroundStyle(Color.journalInk.opacity(0.7))
                        }
                    }
                    .accessibilityIdentifier("include-health-\(metric.rawValue)")
                }
            } header: {
                Text("Use in the app")
            } footer: {
                Text(
                    "Turning an input off excludes it from Today, readiness, trends, and experiment outcomes. Imported records remain on this device and can be used again if you turn it back on."
                )
            }
        }
        .navigationTitle("Apple Health Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView(
        whoopRepository: PreviewWhoopRepository(),
        healthKitRepository: PreviewHealthKitRepository(),
        assessmentRepository: PreviewAssessmentRepository()
    )
}
