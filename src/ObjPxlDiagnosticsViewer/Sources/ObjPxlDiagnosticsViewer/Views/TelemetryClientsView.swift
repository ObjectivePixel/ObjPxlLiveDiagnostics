import CloudKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ClientFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case forced = "Forced"
    case inactive = "Inactive"

    var id: Self { self }

    var isEnabledValue: Bool? {
        switch self {
        case .all, .forced:
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
    var isForceOn: Bool { client.isForceOn }
    var userRecordId: String? { client.userRecordId }

    init(_ telemetryClient: TelemetryClientRecord) {
        client = telemetryClient
        id = telemetryClient.recordID ?? CKRecord.ID(recordName: telemetryClient.clientId)
    }

    static func == (lhs: TelemetryClientDisplay, rhs: TelemetryClientDisplay) -> Bool {
        lhs.id == rhs.id && lhs.isEnabled == rhs.isEnabled && lhs.isForceOn == rhs.isForceOn
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isEnabled)
        hasher.combine(isForceOn)
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
    @State private var scenarioCounts: [String: Int] = [:]
    @State private var showAddClientSheet = false
    @State private var addClientCode = ""
    @State private var isSendingActivation = false
    @State private var addClientError: String?
    @Environment(\.scenePhase) private var scenePhase

    private var filteredClients: [TelemetryClientDisplay] {
        switch filter {
        case .all:
            return clients
        case .active:
            return clients.filter(\.isEnabled)
        case .forced:
            return clients.filter(\.isForceOn)
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
                requestDeleteAll: { showDeleteAllConfirmation = true },
                requestAddClient: { showAddClientSheet = true }
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
                    description: Text(clients.isEmpty ? emptyStateMessage : "Try a different filter to see more clients")
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
                        } else if client.isForceOn {
                            Label("Forced", systemImage: "bolt.circle.fill")
                                .foregroundStyle(.purple)
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

                    TableColumn("User Record ID") { client in
                        Text(client.userRecordId ?? "—")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    TableColumn("Scenarios") { client in
                        let count = scenarioCounts[client.clientId] ?? 0
                        if count > 0 {
                            Label("\(count)", systemImage: "tag")
                                .font(.body)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .width(min: 50, ideal: 80, max: 120)

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
                .contextMenu(forSelectionType: CKRecord.ID.self) { selectedIDs in
                    if let clientID = selectedIDs.first,
                       let client = filteredClients.first(where: { $0.id == clientID }) {
                        Button("Copy Client Code", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(client.clientId, forType: .string)
                        }
                        if let userRecordId = client.userRecordId {
                            Button("Copy User Record ID", systemImage: "square.on.square") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(userRecordId, forType: .string)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                #else
                TelemetryClientsListView(
                    clients: filteredClients,
                    isLoading: isLoading,
                    isDeletingAll: isDeletingAll,
                    togglingClientID: togglingClientID,
                    scenarioCounts: scenarioCounts,
                    toggleClientState: toggleClientState
                )
                .navigationDestination(for: TelemetryClientDisplay.self) { client in
                    ClientScenariosView(client: client)
                }
                #endif
            }
        }
        .padding()
        .navigationTitle("Clients (\(filteredClients.count))")
        .task {
            await setupClientSubscription()
            await fetchClients()
        }
        .onReceive(NotificationCenter.default.publisher(for: .telemetryClientsDidChange)) { _ in
            Task { await fetchClientsWithRetry() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await fetchClients() }
            }
        }
        .onChange(of: filter) { _, _ in
            Task { await fetchClients() }
        }
        .alert("Deactivate All Clients", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Deactivate All", role: .destructive) {
                Task { await deactivateAllClients() }
            }
        } message: {
            Text("This will send a disable command to all \(clients.count) active clients. Clients will remove their own records when they process the command.")
        }
        .sheet(isPresented: $showAddClientSheet) {
            AddClientView(
                clientCode: $addClientCode,
                isSending: isSendingActivation,
                errorMessage: addClientError,
                onSubmit: { await sendActivationCommand() },
                onCancel: {
                    addClientCode = ""
                    addClientError = nil
                    showAddClientSheet = false
                }
            )
        }
        #if os(iOS)
        .toolbar {
            TelemetryClientsToolbarView(
                isLoading: isLoading,
                isDeletingAll: isDeletingAll,
                clients: clients,
                fetchClients: fetchClients,
                requestDeleteAll: { showDeleteAllConfirmation = true },
                requestAddClient: { showAddClientSheet = true }
            )
        }
        #endif
    }

    private func fetchClients() async {
        guard let cloudKitClient else { return }
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
            // Always fetch all clients, filter locally via filteredClients
            let fetchedClients = try await cloudKitClient.fetchTelemetryClients(isEnabled: nil)
            let mapped = fetchedClients.map(TelemetryClientDisplay.init)

            // Also fetch scenario counts for each client
            let counts = await fetchScenarioCounts(cloudKitClient: cloudKitClient)

            await MainActor.run {
                clients = mapped
                scenarioCounts = counts
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

    /// Fetches clients with retry logic for CloudKit propagation delay
    private func fetchClientsWithRetry() async {
        guard let cloudKitClient else { return }

        let previousCount = await MainActor.run { clients.count }

        // CloudKit notifications can arrive before data is visible
        // Retry a few times with delays to handle propagation
        for attempt in 1...3 {
            // Small delay before first attempt, longer for retries
            let delay = attempt == 1 ? 0.3 : 0.5
            try? await Task.sleep(for: .seconds(delay))

            do {
                let fetchedClients = try await cloudKitClient.fetchTelemetryClients(isEnabled: nil)
                let mapped = fetchedClients.map(TelemetryClientDisplay.init)

                // If count changed, we got new data
                if mapped.count != previousCount {
                    await MainActor.run {
                        clients = mapped
                    }
                    print("📡 [Viewer] fetchClientsWithRetry: found \(mapped.count) clients on attempt \(attempt)")
                    return
                }
            } catch {
                print("❌ [Viewer] fetchClientsWithRetry attempt \(attempt) failed: \(error)")
            }
        }

        // Final fetch regardless
        await fetchClients()
    }

    private func setupClientSubscription() async {
        guard let cloudKitClient else { return }

        do {
            // Check if subscription already exists
            let subscriptionID = "TelemetryClient-All"
            if let _ = try await cloudKitClient.fetchSubscription(id: subscriptionID) {
                print("📡 [Viewer] TelemetryClient subscription already exists")
                return
            }

            // Create new subscription
            let newID = try await cloudKitClient.createClientRecordSubscription()
            print("📡 [Viewer] Created TelemetryClient subscription: \(newID)")
        } catch {
            print("❌ [Viewer] Failed to setup client subscription: \(error)")
        }
    }

    private var emptyStateMessage: String {
        #if os(macOS)
        "No clients registered. Click + to add a client using their code."
        #else
        "No clients registered. Tap + to add a client using their code."
        #endif
    }

    private func sendActivationCommand() async {
        guard let cloudKitClient else { return }
        let trimmedCode = addClientCode.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmedCode.isEmpty else {
            addClientError = "Please enter a client code."
            return
        }

        isSendingActivation = true
        addClientError = nil

        do {
            let command = TelemetryCommandRecord(
                clientId: trimmedCode,
                action: .activate
            )
            let saved = try await cloudKitClient.createCommand(command)
            print("[Viewer] Activation command created: \(saved.commandId) for client: \(trimmedCode)")

            addClientCode = ""
            showAddClientSheet = false
        } catch {
            addClientError = "Failed to send activation command: \(error.localizedDescription)"
        }

        isSendingActivation = false
    }

    private func deactivateAllClients() async {
        guard let cloudKitClient else { return }
        isDeletingAll = true
        errorMessage = nil

        do {
            for client in clients where client.isEnabled {
                let command = TelemetryCommandRecord(
                    clientId: client.clientId,
                    action: .disable
                )
                _ = try await cloudKitClient.createCommand(command)
            }
            print("[Viewer] Sent disable commands to all active clients")
        } catch {
            errorMessage = error.localizedDescription
        }

        isDeletingAll = false
    }

    private nonisolated func fetchScenarioCounts(cloudKitClient: CloudKitClient) async -> [String: Int] {
        do {
            let allScenarios = try await cloudKitClient.fetchScenarios(forClient: nil)
            var counts: [String: Int] = [:]
            for scenario in allScenarios {
                counts[scenario.clientId, default: 0] += 1
            }
            return counts
        } catch {
            print("[Viewer] Failed to fetch scenario counts: \(error)")
            return [:]
        }
    }

    private func toggleClientState(for clientRecord: TelemetryClientDisplay) async {
        guard let cloudKitClient else { return }
        togglingClientID = clientRecord.id
        errorMessage = nil

        guard clientRecord.client.recordID != nil else {
            errorMessage = "Missing CloudKit record identifier for client."
            togglingClientID = nil
            return
        }

        let targetState = !clientRecord.isEnabled

        do {
            let commandAction: TelemetrySchema.CommandAction = targetState ? .enable : .disable
            let command = TelemetryCommandRecord(
                clientId: clientRecord.clientId,
                action: commandAction
            )
            print("[Viewer] Creating command: \(commandAction.rawValue) for client: \(clientRecord.clientId)")
            let savedCommand = try await cloudKitClient.createCommand(command)
            print("[Viewer] Command created with ID: \(savedCommand.commandId)")

            // Do not update the client record directly — the client owns it
            // Wait for the client to process the command and update its own record
            await refreshClientStatus(for: clientRecord.id, expectedState: targetState)
        } catch {
            print("[Viewer] Failed to toggle client state: \(error)")
            errorMessage = error.localizedDescription
        }

        togglingClientID = nil
    }

    private func refreshClientStatus(for id: CKRecord.ID, expectedState: Bool) async {
        guard let cloudKitClient else { return }
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
