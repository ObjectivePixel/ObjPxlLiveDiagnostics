import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

enum ClientFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case inactive = "Inactive"

    var id: Self { self }

    var isEnabledValue: Bool? {
        switch self {
        case .all:
            return nil
        case .active:
            return true
        case .inactive:
            return false
        }
    }
}

struct TelemetryClientDisplay: Identifiable, Hashable {
    let id: CKRecord.ID
    let client: TelemetryClientRecord

    var clientId: String { client.clientId }
    var created: Date { client.created }
    var isEnabled: Bool { client.isEnabled }

    init(_ telemetryClient: TelemetryClientRecord) {
        client = telemetryClient
        id = telemetryClient.recordID ?? CKRecord.ID(recordName: telemetryClient.clientId)
    }

    static func == (lhs: TelemetryClientDisplay, rhs: TelemetryClientDisplay) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct TelemetryClientsView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    @State private var clients: [TelemetryClientDisplay] = []
    @State private var filter: ClientFilter = .all
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var togglingClientID: CKRecord.ID?
    @State private var selection = Set<CKRecord.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Picker("Filter", selection: $filter) {
                    ForEach(ClientFilter.allCases) { option in
                        Text(option.rawValue)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Button("Fetch Clients", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await fetchClients() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)

                if isLoading {
                    ProgressView()
                        .padding(.leading, 8)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if clients.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Clients",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Tap \"Fetch Clients\" to load client records")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(clients, selection: $selection) {
                    TableColumn("Client ID") { client in
                        Text(client.clientId)
                            .font(.headline)
                    }

                    TableColumn("Status") { client in
                        Label(
                            client.isEnabled ? "Active" : "Inactive",
                            systemImage: client.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                        )
                        .foregroundStyle(client.isEnabled ? .green : .orange)
                    }

                    TableColumn("Created") { client in
                        Text(client.created, format: .dateTime.year().month().day().hour().minute())
                            .font(.system(.body, design: .monospaced))
                    }

                    TableColumn("Record Name") { client in
                        Text(client.id.recordName)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    TableColumn("Actions") { client in
                        Button(
                            client.isEnabled ? "Deactivate" : "Activate",
                            systemImage: client.isEnabled ? "pause.fill" : "play.fill"
                        ) {
                            Task { await toggleClientState(for: client) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isLoading || togglingClientID == client.id)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding()
        .navigationTitle("Clients (\(clients.count))")
    }

    private func fetchClients() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let fetchedClients = try await cloudKitClient.fetchTelemetryClients(isEnabled: filter.isEnabledValue)
            let mapped = fetchedClients.map(TelemetryClientDisplay.init)
            await MainActor.run {
                clients = mapped
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    private func toggleClientState(for clientRecord: TelemetryClientDisplay) async {
        await MainActor.run {
            togglingClientID = clientRecord.id
            errorMessage = nil
        }

        guard clientRecord.client.recordID != nil else {
            await MainActor.run {
                errorMessage = "Missing CloudKit record identifier for client."
                togglingClientID = nil
            }
            return
        }

        do {
            let updatedClient = TelemetryClientRecord(
                recordID: clientRecord.id,
                clientId: clientRecord.clientId,
                created: clientRecord.created,
                isEnabled: !clientRecord.isEnabled
            )

            let savedClient = try await cloudKitClient.updateTelemetryClient(updatedClient)
            let mapped = TelemetryClientDisplay(savedClient)

            await MainActor.run {
                if let index = clients.firstIndex(where: { $0.id == clientRecord.id }) {
                    clients[index] = mapped
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            togglingClientID = nil
        }
    }
}
