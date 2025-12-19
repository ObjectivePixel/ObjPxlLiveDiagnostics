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
    @State private var isDeletingAll = false
    @State private var errorMessage: String?
    @State private var togglingClientID: CKRecord.ID?
    @State private var selection = Set<CKRecord.ID>()
    @State private var showDeleteAllConfirmation = false

    private var filteredClients: [TelemetryClientDisplay] {
        switch filter {
        case .all:
            return clients
        case .active:
            return clients.filter(\.isEnabled)
        case .inactive:
            return clients.filter { !$0.isEnabled }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(macOS)
            TelemetryClientsHeaderView(
                filter: $filter,
                isLoading: isLoading,
                isDeletingAll: isDeletingAll,
                clients: clients,
                fetchClients: fetchClients,
                requestDeleteAll: { showDeleteAllConfirmation = true }
            )
            #else
            TelemetryClientsFilterView(filter: $filter)
            #endif

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if filteredClients.isEmpty && !isLoading {
                ContentUnavailableView(
                    clients.isEmpty ? "No Clients" : "No Matching Clients",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(clients.isEmpty ? "Tap \"Fetch Clients\" to load client records" : "Try a different filter to see more clients")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                #if os(macOS)
                Table(filteredClients, selection: $selection) {
                    TableColumn("Client ID") { client in
                        Text(client.clientId)
                            .font(.headline)
                    }

                    TableColumn("Status") { client in
                        if togglingClientID == client.id {
                            Label("Updating...", systemImage: "clock.arrow.2.circlepath")
                                .foregroundStyle(.secondary)
                        } else {
                            Label(
                                client.isEnabled ? "Active" : "Inactive",
                                systemImage: client.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                            )
                            .foregroundStyle(client.isEnabled ? .green : .orange)
                        }
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
                        .disabled(isLoading || isDeletingAll || togglingClientID == client.id)
                    }
                }
                .frame(maxHeight: .infinity)
                #else
                TelemetryClientsListView(
                    clients: filteredClients,
                    isLoading: isLoading,
                    isDeletingAll: isDeletingAll,
                    togglingClientID: togglingClientID,
                    toggleClientState: toggleClientState
                )
                #endif
            }
        }
        .padding()
        .navigationTitle("Clients (\(filteredClients.count))")
        .onChange(of: filter) { _, _ in
            Task { await fetchClients() }
        }
        .alert("Delete All Clients", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                Task { await deleteAllClients() }
            }
        } message: {
            Text("Are you sure you want to delete all \(clients.count) client records? This action cannot be undone.")
        }
        #if os(iOS)
        .toolbar {
            TelemetryClientsToolbarView(
                isLoading: isLoading,
                isDeletingAll: isDeletingAll,
                clients: clients,
                fetchClients: fetchClients,
                requestDeleteAll: { showDeleteAllConfirmation = true }
            )
        }
        #endif
    }

    private func fetchClients() async {
        let isAlreadyLoading = await MainActor.run { () -> Bool in
            if isLoading {
                return true
            }
            isLoading = true
            errorMessage = nil
            return false
        }
        guard !isAlreadyLoading else { return }

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

    private func deleteAllClients() async {
        await MainActor.run {
            isDeletingAll = true
            errorMessage = nil
        }

        do {
            _ = try await cloudKitClient.deleteAllTelemetryClients()
            await MainActor.run {
                clients = []
                selection.removeAll()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isDeletingAll = false
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

        let targetState = !clientRecord.isEnabled

        do {
            let updatedClient = TelemetryClientRecord(
                recordID: clientRecord.id,
                clientId: clientRecord.clientId,
                created: clientRecord.created,
                isEnabled: targetState
            )

            let savedClient = try await cloudKitClient.updateTelemetryClient(updatedClient)
            let mapped = TelemetryClientDisplay(savedClient)

            await MainActor.run {
                if let index = clients.firstIndex(where: { $0.id == clientRecord.id }) {
                    clients[index] = mapped
                }
            }
            await refreshClientStatus(for: clientRecord.id, expectedState: targetState)
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            togglingClientID = nil
        }
    }

    private func refreshClientStatus(for id: CKRecord.ID, expectedState: Bool) async {
        for _ in 0..<4 {
            await MainActor.run {
                errorMessage = nil
            }

            do {
                let fetched = try await cloudKitClient.fetchTelemetryClients(isEnabled: filter.isEnabledValue)
                let mapped = fetched.map(TelemetryClientDisplay.init)
                let didUpdate = mapped.first(where: { $0.id == id })?.isEnabled == expectedState

                await MainActor.run {
                    clients = mapped
                }

                if didUpdate {
                    return
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }

            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
