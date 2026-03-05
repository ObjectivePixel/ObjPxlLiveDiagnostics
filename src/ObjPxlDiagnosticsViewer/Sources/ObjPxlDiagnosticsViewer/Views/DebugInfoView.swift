import SwiftUI

struct DebugInfoView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient
    @State private var debugInfo: DebugInfo?
    @State private var isLoading = false

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
                        ])

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
        debugInfo = await cloudKitClient.getDebugInfo()
        isLoading = false
    }
}

struct InfoSection: View {
    let title: String
    let content: [(String, String)]

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
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(.rect(cornerRadius: 8))
        }
    }
}
