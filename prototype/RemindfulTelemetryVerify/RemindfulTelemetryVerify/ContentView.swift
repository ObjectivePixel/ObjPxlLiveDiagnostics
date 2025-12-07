//
//  ContentView.swift
//  RemindfulTelemetryVerify
//
//  Created by James Clarke on 12/5/25.
//

import SwiftUI
import CloudKit

struct ContentView: View {
    @State private var records: [CKRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedAction: SidebarAction? = .records
    @State private var currentEnvironment = "Detecting..."
    @State private var isClearing = false
    @State private var showClearConfirmation = false
    
    private let client = CloudKitClient()
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selectedAction: $selectedAction, currentEnvironment: currentEnvironment) {
                Task {
                    await client.validateSchema()
                }
            }
        } detail: {
            // Detail View
            DetailView(
                selectedAction: selectedAction,
                records: records,
                isLoading: isLoading,
                errorMessage: errorMessage,
                fetchRecords: fetchRecords,
                clearRecords: clearRecords,
                isClearing: isClearing,
                showClearConfirmation: $showClearConfirmation
            )
        }
        .task {
            // Detect environment on startup
            currentEnvironment = await client.detectEnvironment()
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
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedRecords = try await client.fetchAllRecords()
            await MainActor.run {
                self.records = fetchedRecords
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
        
        isLoading = false
    }
    
    private func clearRecords() {
        showClearConfirmation = true
    }
    
    private func performClear() async {
        isClearing = true
        errorMessage = nil
        
        do {
            let deletedCount = try await client.deleteAllRecords()
            await MainActor.run {
                self.records = []
                print("🗑️ UI cleared: removed \(deletedCount) records from display")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to clear records: \(error.localizedDescription)"
            }
        }
        
        isClearing = false
    }
}

enum SidebarAction: String, CaseIterable, Identifiable {
    case records = "Records"
    case schema = "Schema"
    case debug = "Debug Info"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .records:
            return "list.bullet.rectangle"
        case .schema:
            return "gear.badge.checkmark"
        case .debug:
            return "info.circle"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedAction: SidebarAction?
    let currentEnvironment: String
    let validateSchema: () -> Void
    
    var body: some View {
        List(SidebarAction.allCases, selection: $selectedAction) { action in
            NavigationLink(value: action) {
                Label(action.rawValue, systemImage: action.systemImage)
            }
        }
        .navigationTitle("Telemetry Tools")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Validate Schema", action: validateSchema)
                    .buttonStyle(.bordered)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading) {
                Text("CloudKit Environment:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(currentEnvironment)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(currentEnvironment.contains("Development") ? .blue : .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    }
}

struct DetailView: View {
    let selectedAction: SidebarAction?
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    @Binding var showClearConfirmation: Bool
    
    private let client = CloudKitClient()
    
    var body: some View {
        Group {
            switch selectedAction {
            case .records:
                RecordsListView(
                    records: records,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    fetchRecords: fetchRecords,
                    clearRecords: clearRecords,
                    isClearing: isClearing
                )
            case .schema:
                SchemaView()
            case .debug:
                DebugInfoView(client: client)
            case .none:
                ContentUnavailableView(
                    "Select a Tool",
                    systemImage: "sidebar.left",
                    description: Text("Choose an option from the sidebar to get started")
                )
            }
        }
    }
}

struct RecordsListView: View {
    let records: [CKRecord]
    let isLoading: Bool
    let errorMessage: String?
    let fetchRecords: () async -> Void
    let clearRecords: () -> Void
    let isClearing: Bool
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isClearing {
                ProgressView("Clearing all records...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if records.isEmpty {
                ContentUnavailableView(
                    "No Records Found",
                    systemImage: "tray",
                    description: Text("Tap 'Fetch Records' to load telemetry data from CloudKit")
                )
            } else {
                TelemetryTableView(records: records)
            }
            
            if let errorMessage = errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundColor(.red)
                    .padding()
            }
        }
        .navigationTitle("Telemetry Records (\(records.count))")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Clear All") {
                    clearRecords()
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .disabled(isLoading || isClearing || records.isEmpty)
                
                Button("Fetch Records") {
                    Task {
                        await fetchRecords()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isClearing)
            }
        }
    }
}

struct SchemaView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CloudKit Schema")
                .font(.largeTitle)
                .bold()
            
            Text("Record Type: \(TelemetrySchema.recordType)")
                .font(.headline)
            
            Text("Fields:")
                .font(.headline)
                .padding(.top)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TelemetrySchema.Field.allCases, id: \.rawValue) { field in
                    HStack {
                        Text(field.rawValue)
                            .font(.monospaced(.body)())
                        Spacer()
                        if field.isIndexed {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.blue)
                                .help("Queryable/Indexed")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Schema")
    }
}

struct TelemetryTableView: View {
    let records: [CKRecord]
    @State private var sortOrder = [KeyPathComparator(\TelemetryRecord.eventTimestamp, order: .reverse)]
    @State private var selection = Set<TelemetryRecord.ID>()
    
    private var sortedRecords: [TelemetryRecord] {
        let telemetryRecords = records.map(TelemetryRecord.init)
        return telemetryRecords.sorted(using: sortOrder)
    }
    
    var body: some View {
        Table(sortedRecords, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Timestamp", value: \.eventTimestamp) { record in
                Text(record.formattedTimestamp)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 95, ideal: 120, max: 170)
            
            TableColumn("Event Name", value: \.eventName) { record in
                Text(record.eventName)
                    .font(.headline)
            }
            .width(min: 120, ideal: 180, max: 300)
            
            TableColumn("Property 1", value: \.property1) { record in
                Text(record.property1)
                    .font(.body)
                    .help(record.property1)
            }
            .width(min: 200, ideal: 400, max: 800)
            
            TableColumn("Device Type", value: \.deviceType) { record in
                Label(record.deviceType, systemImage: "devices")
                    .font(.body)
            }
            .width(min: 50, ideal: 65, max: 100)
            
            TableColumn("App Version", value: \.appVersion) { record in
                Label("v\(record.appVersion)", systemImage: "app.badge")
                    .font(.body)
            }
            .width(min: 40, ideal: 60, max: 90)
            
            TableColumn("Thread ID", value: \.threadId) { record in
                Text(record.threadId)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(min: 40, ideal: 50, max: 75)
        }
        #if os(macOS)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        #endif
    }
}

// Model for Table rows
struct TelemetryRecord: Identifiable {
    let id = UUID()
    let eventId: String
    let eventName: String
    let eventTimestamp: Date
    let deviceType: String
    let deviceName: String
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let threadId: String
    let property1: String
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: eventTimestamp)
    }
    
    init(_ record: CKRecord) {
        self.eventId = record.recordID.recordName
        self.eventName = record[TelemetrySchema.Field.eventName.rawValue] as? String ?? "Unknown"
        self.eventTimestamp = record[TelemetrySchema.Field.eventTimestamp.rawValue] as? Date ?? Date()
        self.deviceType = record[TelemetrySchema.Field.deviceType.rawValue] as? String ?? "N/A"
        self.deviceName = record[TelemetrySchema.Field.deviceName.rawValue] as? String ?? "N/A"
        self.deviceModel = record[TelemetrySchema.Field.deviceModel.rawValue] as? String ?? "N/A"
        self.osVersion = record[TelemetrySchema.Field.osVersion.rawValue] as? String ?? "N/A"
        self.appVersion = record[TelemetrySchema.Field.appVersion.rawValue] as? String ?? "N/A"
        self.threadId = record[TelemetrySchema.Field.threadId.rawValue] as? String ?? "N/A"
        self.property1 = record[TelemetrySchema.Field.property1.rawValue] as? String ?? "N/A"
    }
}

struct RecordCard: View {
    let record: CKRecord
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record[TelemetrySchema.Field.eventName.rawValue] as? String ?? "Unknown Event")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            
            if let timestamp = record[TelemetrySchema.Field.eventTimestamp.rawValue] as? Date {
                Text(timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let deviceType = record[TelemetrySchema.Field.deviceType.rawValue] as? String {
                    Label(deviceType, systemImage: "devices")
                        .font(.caption)
                }
                
                if let appVersion = record[TelemetrySchema.Field.appVersion.rawValue] as? String {
                    Label("v\(appVersion)", systemImage: "app.badge")
                        .font(.caption)
                }
                
                if let osVersion = record[TelemetrySchema.Field.osVersion.rawValue] as? String {
                    Label(osVersion, systemImage: "gear")
                        .font(.caption)
                }
            }
            
            Text("ID: \(record.recordID.recordName)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

struct DebugInfoView: View {
    let client: CloudKitClient
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
            } else if let debugInfo = debugInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        InfoSection(title: "Environment", content: [
                            ("Container ID", debugInfo.containerID),
                            ("Build Type", debugInfo.buildType),
                            ("Environment", debugInfo.environment)
                        ])
                        
                        InfoSection(title: "Query Results", content: [
                            ("Test Query Results", "\(debugInfo.testQueryResults)"),
                            ("First Record ID", debugInfo.firstRecordID ?? "N/A")
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
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.05))
                            .cornerRadius(8)
                        }
                        
                        if let errorMessage = debugInfo.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Error Information")
                                    .font(.headline)
                                    .foregroundColor(.red)
                                
                                Text(errorMessage)
                                    .font(.body)
                                    .padding()
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(8)
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
        isLoading = true
        debugInfo = await client.getDebugInfo()
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
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.1)
                            .font(.monospaced(.body)())
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }
}

#Preview {
    ContentView()
}
