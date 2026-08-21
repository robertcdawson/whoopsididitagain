import SwiftUI

struct TrendsView: View {
    let whoopRepository: any WhoopRepository
    let healthKitRepository: any HealthKitRepository

    @State private var history = WhoopHistorySnapshot(
        recoveries: [],
        sleeps: [],
        lastSyncAt: nil
    )
    @State private var errorMessage: String?
    @State private var healthHistory = HealthKitHistorySnapshot(
        days: [], lastSyncAt: nil, recordCount: 0, linkedWorkoutCount: 0
    )

    var body: some View {
        NavigationStack {
            Group {
                if history.recoveries.isEmpty && history.sleeps.isEmpty
                    && healthHistory.days.isEmpty
                {
                    ContentUnavailableView {
                        Label("No trends yet", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(
                            "Connect WHOOP or Apple Health in Settings, then synchronize your history."
                        )
                    }
                } else {
                    List {
                        if let lastSyncAt = history.lastSyncAt {
                            Section {
                                LabeledContent(
                                    "Last synchronized",
                                    value: lastSyncAt.formatted(
                                        date: .abbreviated, time: .shortened)
                                )
                            }
                        }

                        Section("Recovery") {
                            ForEach(history.recoveries) { item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.timestamp, format: .dateTime.month().day())
                                        if let restingHeartRate = item.restingHeartRate {
                                            Text("Resting HR \(restingHeartRate) bpm")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(item.recoveryScore.map(String.init) ?? "—")
                                        .font(.title2.weight(.semibold))
                                }
                            }
                        }

                        Section("Apple Health physiology") {
                            ForEach(healthHistory.days) { day in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(day.day)
                                        .font(.headline)
                                    if let hrv = day.hrvSDNNMilliseconds {
                                        LabeledContent(
                                            "HRV SDNN",
                                            value:
                                                "\(hrv.formatted(.number.precision(.fractionLength(1)))) ms"
                                        )
                                    }
                                    if let resting = day.restingHeartRate {
                                        LabeledContent(
                                            "Resting HR",
                                            value:
                                                "\(resting.formatted(.number.precision(.fractionLength(0)))) bpm"
                                        )
                                    }
                                    if let sleep = day.sleepMinutes {
                                        LabeledContent(
                                            "Sleep", value: "\(sleep / 60)h \(sleep % 60)m")
                                    }
                                    Text("Source: \(day.sources.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section("Sleep") {
                            ForEach(history.sleeps) { item in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.start, format: .dateTime.month().day())
                                        Text(item.isNap ? "Nap" : "Sleep")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let minutes = item.sleepMinutes {
                                        Text("\(minutes / 60)h \(minutes % 60)m")
                                    } else {
                                        Text("—")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Trends")
            .task { await loadHistory() }
            .refreshable { await synchronizeAndLoad() }
            .alert("Couldn’t load history", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @MainActor
    private func loadHistory() async {
        do {
            async let whoop = whoopRepository.history()
            async let health = healthKitRepository.history()
            history = try await whoop
            healthHistory = try await health
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func synchronizeAndLoad() async {
        do {
            let status = try await whoopRepository.connectionStatus()
            if status.connected {
                _ = try await whoopRepository.synchronize()
            }
            if await healthKitRepository.authorizationState() == .requested {
                _ = try await healthKitRepository.synchronize()
            }
            history = try await whoopRepository.history()
            healthHistory = try await healthKitRepository.history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TrendsView(
        whoopRepository: PreviewWhoopRepository(),
        healthKitRepository: PreviewHealthKitRepository()
    )
}
