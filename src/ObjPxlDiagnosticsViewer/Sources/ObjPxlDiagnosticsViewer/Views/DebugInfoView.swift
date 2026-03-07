import SwiftUI
import ObjPxlDiagnosticsShared
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct DebugInfoView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient
    @State private var debugInfo: DebugInfo?
    @State private var isLoading = false
    @State private var recordCounts: [(String, String)]?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CloudKit Debug Information")
                .font(.largeTitle)
                .bold()

            if isLoading {
                ProgressView("Loading debug info...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let debugInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        InfoSection(title: "Environment", content: [
                            ("Container ID", debugInfo.containerID),
                            ("User Record ID", debugInfo.userRecordID ?? "N/A"),
                            ("Build Type", debugInfo.buildType),
                            ("Environment", debugInfo.environment)
                        ], copyableKeys: ["User Record ID"])

                        if let recordCounts {
                            InfoSection(title: "Record Counts", content: recordCounts)
                        }

                        InfoSection(title: "Query Results", content: [
                            ("Test Query Results", "\(debugInfo.testQueryResults)"),
                            ("First Record ID", debugInfo.firstRecordID ?? "N/A"),
                            ("Total Records (scan)", debugInfo.recordCount.map(String.init) ?? "N/A")
                        ])

                        if !debugInfo.firstRecordFields.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("First Record Fields")
                                    .font(.headline)

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 8) {
                                    ForEach(debugInfo.firstRecordFields, id: \.self) { field in
                                        Text(field)
                                            .font(.monospaced(.body)())
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(.rect(cornerRadius: 6))
                                    }
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .clipShape(.rect(cornerRadius: 8))
                        }

                        if let errorMessage = debugInfo.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Error Information")
                                    .font(.headline)
                                    .foregroundStyle(.red)

                                Text(errorMessage)
                                    .font(.body)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "No Debug Information",
                    systemImage: "info.circle",
                    description: Text("Tap 'Refresh' to load debug information")
                )
            }
        }
        .navigationTitle("Debug Info")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh") {
                    Task {
                        await loadDebugInfo()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .task {
            await loadDebugInfo()
        }
    }

    private func loadDebugInfo() async {
        guard let cloudKitClient else { return }
        isLoading = true

        async let debugInfoTask = cloudKitClient.getDebugInfo()
        async let countsTask = fetchRecordCounts(cloudKitClient: cloudKitClient)

        debugInfo = await debugInfoTask
        recordCounts = await countsTask

        isLoading = false
    }

    private nonisolated func fetchRecordCounts(cloudKitClient: CloudKitClient) async -> [(String, String)] {
        let types: [(String, String)] = [
            ("Events", TelemetrySchema.recordType),
            ("Clients", TelemetrySchema.clientRecordType),
            ("Scenarios", TelemetrySchema.scenarioRecordType),
            ("Commands", TelemetrySchema.commandRecordType),
        ]

        return await withTaskGroup(of: (String, String).self) { group in
            for (label, recordType) in types {
                group.addTask {
                    let count = (try? await cloudKitClient.countRecords(ofType: recordType)) ?? 0
                    return (label, "\(count)")
                }
            }

            var results: [(String, String)] = []
            for await result in group {
                results.append(result)
            }
            // Preserve display order
            return types.compactMap { label, _ in results.first { $0.0 == label } }
        }
    }
}

struct InfoSection: View {
    let title: String
    let content: [(String, String)]
    var copyableKeys: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(content, id: \.0) { item in
                    HStack {
                        Text(item.0 + ":")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.1)
                            .font(.monospaced(.body)())
                            .foregroundStyle(.primary)
                        if copyableKeys.contains(item.0) && item.1 != "N/A" {
                            Button {
                                #if canImport(UIKit)
                                UIPasteboard.general.string = item.1
                                #else
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.1, forType: .string)
                                #endif
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Copy \(item.0)")
                        }
                    }
                    .contextMenu {
                        Button("Copy", systemImage: "doc.on.doc") {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = item.1
                            #else
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.1, forType: .string)
                            #endif
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
