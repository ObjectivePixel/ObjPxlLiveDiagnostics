//
//  ContentView.swift
//  RemindfulTelemetryVerify
//
//  Created by James Clarke on 12/5/25.
//

import CloudKit
import ObjPxlLiveTelemetry
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

    private let pageSize = 200

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
                showClearConfirmation: $showClearConfirmation
            )
        }
        .task {
            guard let cloudKitClient else { return }
            currentEnvironment = await cloudKitClient.detectEnvironment()
        }
        .alert("Clear All Records", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                Task {
                    await performClear()
                }
            }
        } message: {
            Text("Are you sure you want to delete all \(records.count) telemetry records? This action cannot be undone.")
        }
    }

    private func fetchRecords() async {
        guard let cloudKitClient else { return }
        isLoading = true
        isLoadingMore = false
        errorMessage = nil
        nextCursor = nil

        do {
            let result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: nil)
            await MainActor.run {
                records = result.0
                nextCursor = result.1
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
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
            let deletedCount = try await cloudKitClient.deleteAllRecords()
            await MainActor.run {
                records = []
                nextCursor = nil
                print("🗑️ UI cleared: removed \(deletedCount) records from display")
            }
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
