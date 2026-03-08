//
//  ContentView.swift
//  RemindfulTelemetryVerify
//
//  Created by James Clarke on 12/5/25.
//

import CloudKit
import ObjPxlDiagnosticsShared
import SwiftUI

struct ContentView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient
    @State private var records: [CKRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAction: SidebarAction? = .records
    @State private var currentEnvironment = "Detecting..."
    @State private var isClearing = false
    @State private var showClearConfirmation = false
    @State private var nextCursor: CKQueryOperation.Cursor?
    @State private var isLoadingMore = false
    @State private var scenarioFilter: String?
    @State private var logLevelFilter: TelemetryLogLevel?
    @State private var sessionIdFilter: String?
    @State private var availableScenarios: [String] = []
    @State private var availableSessionIds: [String] = []

    private let pageSize = 200

    private var hasActiveFilters: Bool {
        scenarioFilter != nil || logLevelFilter != nil || sessionIdFilter != nil
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedAction: $selectedAction, currentEnvironment: currentEnvironment) {
                Task {
                    await cloudKitClient?.validateSchema()
                }
            }
        } detail: {
            DetailView(
                selectedAction: selectedAction,
                records: records,
                isLoading: isLoading,
                errorMessage: errorMessage,
                fetchRecords: fetchRecords,
                clearRecords: clearRecords,
                isClearing: isClearing,
                hasMore: nextCursor != nil,
                loadMore: loadMoreRecords,
                isLoadingMore: isLoadingMore,
                scenarioFilter: $scenarioFilter,
                logLevelFilter: $logLevelFilter,
                sessionIdFilter: $sessionIdFilter,
                availableScenarios: availableScenarios,
                availableSessionIds: availableSessionIds,
                showClearConfirmation: $showClearConfirmation,
                hasActiveFilters: hasActiveFilters
            )
        }
        .task {
            guard let cloudKitClient else { return }
            currentEnvironment = await cloudKitClient.detectEnvironment()
            await fetchAvailableScenarios()
        }
        .onChange(of: scenarioFilter) { _, _ in
            Task { await fetchRecords() }
        }
        .onChange(of: logLevelFilter) { _, _ in
            Task { await fetchRecords() }
        }
        .onChange(of: sessionIdFilter) { _, _ in
            Task { await fetchRecords() }
        }
        .alert(
            hasActiveFilters ? "Clear Filtered Records" : "Clear All Records",
            isPresented: $showClearConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button(hasActiveFilters ? "Clear Filtered" : "Clear All", role: .destructive) {
                Task {
                    await performClear()
                }
            }
        } message: {
            if hasActiveFilters {
                Text("Are you sure you want to delete all records matching the current filters? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete all \(records.count) telemetry records? This action cannot be undone.")
            }
        }
    }

    private func fetchRecords() async {
        guard let cloudKitClient else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        nextCursor = nil

        do {
            let result: ([CKRecord], CKQueryOperation.Cursor?)

            if scenarioFilter != nil || logLevelFilter != nil || sessionIdFilter != nil {
                result = try await cloudKitClient.fetchRecords(
                    scenario: scenarioFilter,
                    logLevel: logLevelFilter?.rawValue,
                    sessionId: sessionIdFilter,
                    limit: pageSize,
                    cursor: nil
                )
            } else {
                result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: nil)
            }

            await MainActor.run {
                records = result.0
                nextCursor = result.1
                updateAvailableSessionIds()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func updateAvailableSessionIds() {
        let ids = Set(
            records.compactMap { $0[TelemetrySchema.Field.sessionId.rawValue] as? String }
                .filter { !$0.isEmpty }
        ).sorted()
        availableSessionIds = ids
    }

    private func fetchAvailableScenarios() async {
        guard let cloudKitClient else { return }
        do {
            let scenarios = try await cloudKitClient.fetchScenarios(forClient: nil)
            let names = Set(scenarios.map(\.scenarioName)).sorted()
            await MainActor.run {
                availableScenarios = names
            }
        } catch {
            print("❌ [Viewer] Failed to fetch scenario names: \(error)")
        }
    }

    private func loadMoreRecords() async {
        guard let cloudKitClient, let cursor = nextCursor else { return }

        isLoadingMore = true
        errorMessage = nil

        do {
            let result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: cursor)
            await MainActor.run {
                records.append(contentsOf: result.0)
                nextCursor = result.1
                updateAvailableSessionIds()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        isLoadingMore = false
    }

    private func clearRecords() {
        showClearConfirmation = true
    }

    private func performClear() async {
        guard let cloudKitClient else { return }
        isClearing = true
        errorMessage = nil

        do {
            let deletedCount: Int
            if hasActiveFilters {
                let result = try await cloudKitClient.deleteFilteredRecords(
                    scenario: scenarioFilter,
                    logLevel: logLevelFilter?.rawValue,
                    sessionId: sessionIdFilter
                )
                deletedCount = result.deleted
                if result.failed > 0 {
                    print("⚠️ \(result.failed) record(s) failed to delete")
                }
            } else {
                deletedCount = try await cloudKitClient.deleteAllRecords()
            }
            print("🗑️ Deleted \(deletedCount) records from CloudKit")
            await fetchRecords()
        } catch {
            await MainActor.run {
                errorMessage = "Failed to clear records: \(error.localizedDescription)"
            }
        }

        isClearing = false
    }
}

#Preview {
    ContentView()
        .environment(
            \.cloudKitClient,
            CloudKitClient(containerIdentifier: "iCloud.objectivepixel.prototype.remindful.telemetry")
        )
}
