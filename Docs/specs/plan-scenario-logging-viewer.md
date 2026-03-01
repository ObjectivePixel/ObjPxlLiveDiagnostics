# Plan: Scenario-Based Logging — Viewer App (RemindfulDiagnosticViewer)

This plan covers all changes to the RemindfulDiagnosticViewer app. A separate plan covers the client package (ObjPxlLiveTelemetry repo).

**Prerequisites**: The client package changes must be completed and the package version bumped before this work begins, since this repo imports `ObjPxlLiveTelemetry` and depends on the new types (`TelemetryScenarioRecord`, extended `CommandAction`, extended `TelemetryCommandRecord`, new `CloudKitClientProtocol` methods).

---

## Context

The viewer app is a SwiftUI app (iOS 26.0+, Swift 6.2+) that displays telemetry data from CloudKit. Key architecture points:

- `NavigationSplitView` with `SidebarView` → `DetailView`
- `SidebarAction` enum drives sidebar navigation: `.records`, `.schema`, `.debug`, `.clients`
- `CloudKitClientProtocol` accessed via `@Environment(\.cloudKitClient)`
- No ViewModels — uses `@State` and `@Environment` per AGENTS.md
- Platform-conditional views for macOS (Table) vs iOS (List)
- CloudKit push notifications handled in `AppDelegate`, posted as `Notification.Name` for views to observe
- Existing pattern: `TelemetryClientsView` fetches/displays clients, sends commands, subscribes to changes

---

## Design Decisions (Resolved)

- **Per-client control only**: Each scenario row controls one client. No cross-client grouping or bulk toggles.
- **No history**: Show current scenario state only.
- **Scenarios tab is top-level**: New sidebar entry showing all scenarios grouped by scenario name.
- **Client detail shows scenarios**: Tapping a client navigates to its scenario list with start/stop controls.

---

## Step 1: Add Scenarios to Sidebar

### 1a. `SidebarView.swift` — Add `.scenarios` case

```swift
enum SidebarAction: String, CaseIterable, Identifiable {
    case records = "Records"
    case scenarios = "Scenarios"
    case schema = "Schema"
    case debug = "Debug Info"
    case clients = "Clients"

    var systemImage: String {
        switch self {
        case .records: return "list.bullet.rectangle"
        case .scenarios: return "tag"
        case .schema: return "gear.badge.checkmark"
        case .debug: return "info.circle"
        case .clients: return "person.3"
        }
    }
}
```

### 1b. `DetailView.swift` — Wire the new case

```swift
case .scenarios:
    ScenariosView()
```

---

## Step 2: Create `ScenariosView`

New file: `Views/ScenariosView.swift`

This is the top-level view for the Scenarios sidebar tab. It fetches all scenarios from CloudKit and groups them by scenario name.

```swift
struct ScenariosView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    @State private var scenarios: [TelemetryScenarioRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var togglingScenarioID: CKRecord.ID?

    /// Scenarios grouped by name, sorted alphabetically
    private var groupedScenarios: [(name: String, scenarios: [TelemetryScenarioRecord])] {
        Dictionary(grouping: scenarios, by: \.scenarioName)
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, scenarios: $0.value) }
    }

    var body: some View {
        // Show grouped scenarios or empty state
        // Each group is a ScenarioGroupView
        // .task { await setupSubscription(); await fetchScenarios() }
        // .onReceive(.telemetryScenariosDidChange) { ... }
    }

    private func fetchScenarios() async { /* fetch all via cloudKitClient.fetchScenarios(forClient: nil) */ }
    private func toggleScenario(_ scenario: TelemetryScenarioRecord) async { /* send command + update record */ }
    private func setupSubscription() async { /* createScenarioSubscription() */ }
}
```

**Key behaviors:**
- Fetch all scenarios (no client filter) on appear
- Group by `scenarioName` using `Dictionary(grouping:by:)`
- Subscribe to `TelemetryScenario` CloudKit changes for live updates
- Track `togglingScenarioID` to show loading state on the row being toggled

### Toggle implementation

When a toggle is tapped:
1. Determine the target state (`!scenario.isEnabled`)
2. Create a `TelemetryCommandRecord` with:
   - `clientId` = the scenario's client ID
   - `action` = `.enableScenario` or `.disableScenario`
   - `scenarioName` = the scenario name
3. Save the command via `cloudKitClient.createCommand(_:)`
4. Update the scenario record via `cloudKitClient.updateScenario(_:)` for immediate UI consistency
5. Refresh with retry (same pattern as `TelemetryClientsView.refreshClientStatus`)

---

## Step 3: Create Subviews for Scenario Display

### 3a. `ScenarioGroupView.swift`

Disclosure group showing one scenario name with its per-client rows:

```swift
struct ScenarioGroupView: View {
    let scenarioName: String
    let scenarios: [TelemetryScenarioRecord]
    let togglingScenarioID: CKRecord.ID?
    let toggleScenario: (TelemetryScenarioRecord) async -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(scenarios, id: \.recordID) { scenario in
                ScenarioClientRowView(
                    scenario: scenario,
                    isToggling: togglingScenarioID == scenario.recordID,
                    toggleScenario: { Task { await toggleScenario(scenario) } }
                )
            }
        } label: {
            Label(scenarioName, systemImage: "tag")
                .font(.headline)
                .badge(scenarios.count)
        }
    }
}
```

### 3b. `ScenarioClientRowView.swift`

A single client's row within a scenario group:

```swift
struct ScenarioClientRowView: View {
    let scenario: TelemetryScenarioRecord
    let isToggling: Bool
    let toggleScenario: () -> Void

    var body: some View {
        HStack {
            Text(scenario.clientId)
                .font(.body)

            Spacer()

            if isToggling {
                Label("Updating...", systemImage: "clock.arrow.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    scenario.isEnabled ? "Active" : "Inactive",
                    systemImage: scenario.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                .foregroundStyle(scenario.isEnabled ? .green : .orange)
            }

            Button(
                scenario.isEnabled ? "Disable" : "Enable",
                systemImage: scenario.isEnabled ? "pause.fill" : "play.fill"
            ) {
                toggleScenario()
            }
            .buttonStyle(.bordered)
            .disabled(isToggling)
        }
    }
}
```

---

## Step 4: Create `ClientScenariosView`

New file: `Views/ClientScenariosView.swift`

Shown when navigating from a client row in `TelemetryClientsView`. Lists all scenarios for one specific client.

```swift
struct ClientScenariosView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    let client: TelemetryClientDisplay

    @State private var scenarios: [TelemetryScenarioRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var togglingScenarioID: CKRecord.ID?

    var body: some View {
        List(scenarios, id: \.recordID) { scenario in
            HStack {
                Text(scenario.scenarioName)
                    .font(.headline)

                Spacer()

                // Status label + enable/disable button
                // Same pattern as ScenarioClientRowView
            }
        }
        .navigationTitle(client.clientId)
        .task { await fetchScenarios() }
    }

    private func fetchScenarios() async {
        // cloudKitClient.fetchScenarios(forClient: client.clientId)
    }

    private func toggleScenario(_ scenario: TelemetryScenarioRecord) async {
        // Same toggle pattern as ScenariosView
    }
}
```

---

## Step 5: Add Navigation from Clients to Scenarios

### 5a. Update `TelemetryClientsView`

Make client rows tappable and navigate to `ClientScenariosView`. Add a `@State private var selectedClient: TelemetryClientDisplay?` and use `navigationDestination(for:)`.

For iOS (`TelemetryClientsListView`):
- Wrap each client row in a `NavigationLink(value: client)`
- Add `.navigationDestination(for: TelemetryClientDisplay.self) { client in ClientScenariosView(client: client) }`

For macOS (Table):
- The table selection already tracks `Set<CKRecord.ID>`. On double-click or a "View Scenarios" button in the Actions column, navigate to the client's scenarios.
- Alternatively, add a "Scenarios" `TableColumn` showing the count, with a button to navigate.

### 5b. Update `TelemetryClientRowView`

Optionally show a badge or subtitle with the scenario count for the client. This requires either:
- Pre-fetching scenario counts when loading clients (add a `scenarioCounts: [String: Int]` dictionary to the parent view)
- Or a lightweight fetch in a `.task` modifier on each row (less ideal for performance)

The pre-fetch approach is simpler: in `TelemetryClientsView.fetchClients()`, also fetch all scenarios and build a count map.

---

## Step 6: CloudKit Subscription for Scenarios

### 6a. New notification name

In `TelemetryClientsView.swift` (or a shared file):

```swift
extension Notification.Name {
    static let telemetryScenariosDidChange = Notification.Name("telemetryScenariosDidChange")
}
```

### 6b. `AppDelegate` changes

In the `AppDelegate` (both macOS and iOS), update the push notification handler to recognize the new subscription:

```swift
// Existing: subscription ID starts with "TelemetryClient"
// New: subscription ID starts with "TelemetryScenario"

if subscriptionID.hasPrefix("TelemetryScenario") {
    NotificationCenter.default.post(name: .telemetryScenariosDidChange, object: nil)
}
```

Follow the same pattern used for `.telemetryClientsDidChange`.

### 6c. Subscription setup

In `ScenariosView.setupSubscription()`:

```swift
private func setupSubscription() async {
    guard let cloudKitClient else { return }
    do {
        let subscriptionID = "TelemetryScenario-All"
        if let _ = try await cloudKitClient.fetchSubscription(id: subscriptionID) {
            return  // already exists
        }
        let newID = try await cloudKitClient.createScenarioSubscription()
        print("📡 [Viewer] Created TelemetryScenario subscription: \(newID)")
    } catch {
        print("❌ [Viewer] Failed to setup scenario subscription: \(error)")
    }
}
```

---

## Step 7: Add Scenario Filter to Records Views

### 7a. Add scenario display to `TelemetryRecordRowView`

Show the scenario name as a tag/badge on each log record row:

```swift
// Inside the existing VStack
if let scenario = record.scenario, !scenario.isEmpty {
    Label(scenario, systemImage: "tag")
        .font(.caption)
        .foregroundStyle(.tint)
}
```

This requires adding a `scenario: String?` property to the local `TelemetryRecord` struct (in `TelemetryTableView.swift`), populated from the `TelemetrySchema.Field.scenario` field of the `CKRecord`.

### 7b. Add scenario filter to `RecordsListView`

Add a filter picker above the records list:

```swift
@State private var scenarioFilter: String? = nil  // nil = show all

// Populate from unique scenario names in current records
private var availableScenarios: [String] {
    Set(records.compactMap { /* extract scenario field */ }).sorted()
}

// Picker in toolbar or header
Picker("Scenario", selection: $scenarioFilter) {
    Text("All Scenarios").tag(String?.none)
    ForEach(availableScenarios, id: \.self) { name in
        Text(name).tag(String?.some(name))
    }
}
```

Filter the records list based on the selected scenario before display.

---

## Step 8: Deletion Integration

### 8a. Update `deleteAllClients()`

In `TelemetryClientsView.deleteAllClients()`, also delete all scenarios:

```swift
private func deleteAllClients() async {
    guard let cloudKitClient else { return }
    // ... existing setup ...

    do {
        // Delete all scenarios for each client
        for client in clients {
            _ = try await cloudKitClient.deleteScenarios(forClient: client.clientId)
        }
        // Then delete client records
        _ = try await cloudKitClient.deleteAllTelemetryClients()
        // ... existing cleanup ...
    } catch { ... }
}
```

### 8b. Update delete confirmation

Include scenario information in the confirmation dialog:

```swift
Text("Are you sure you want to delete all \(clients.count) client records and their scenarios? This action cannot be undone.")
```

---

## Step 9: Update Package Dependency

Update the `ObjPxlLiveTelemetry` package reference in the Xcode project to the version that includes the scenario types. This means updating the package version in `Package.resolved` (via Xcode's package resolution or `xcodebuild -resolvePackageDependencies`).

---

## New Files

| File | Description |
|------|-------------|
| `Views/ScenariosView.swift` | Top-level scenarios tab — grouped view with fetch, subscribe, toggle |
| `Views/ScenarioGroupView.swift` | Disclosure group for one scenario name with per-client rows |
| `Views/ScenarioClientRowView.swift` | Single client row within a scenario group |
| `Views/ClientScenariosView.swift` | Per-client scenario list, navigated from Clients tab |

## Modified Files

| File | Changes |
|------|---------|
| `Views/SidebarView.swift` | Add `.scenarios` case to `SidebarAction` |
| `Views/DetailView.swift` | Add `.scenarios` case routing to `ScenariosView` |
| `Views/TelemetryClientsView.swift` | Add navigation to `ClientScenariosView`, scenario count pre-fetch, deletion integration |
| `Views/TelemetryClientsListView.swift` | Add `NavigationLink` wrapping for client rows (iOS) |
| `Views/TelemetryClientRowView.swift` | Optionally show scenario count badge |
| `Views/TelemetryRecordRowView.swift` | Show scenario tag on log records |
| `Views/TelemetryTableView.swift` | Add `scenario` property to `TelemetryRecord` struct |
| `Views/RecordsListView.swift` | Add scenario filter picker |
| `Views/RecordsListIOSView.swift` | Wire scenario filter (iOS) |
| `Views/RecordsListMacView.swift` | Wire scenario filter (macOS) |
| `LiveDiagnosticsViewerApp.swift` | Handle scenario subscription notifications in `AppDelegate` |

---

## Implementation Order

1. **Update package dependency** to get new types (Step 9 — do first once client package is ready)
2. **Sidebar + routing** — Add `.scenarios` to sidebar, wire `DetailView` (Step 1)
3. **ScenariosView + subviews** — Create the grouped scenario display (Steps 2, 3)
4. **CloudKit subscription** — Subscribe to scenario changes, handle notifications (Step 6)
5. **Scenario toggle commands** — Enable/disable scenarios from the viewer (part of Step 2)
6. **ClientScenariosView** — Per-client scenario view (Step 4)
7. **Client navigation** — Wire client rows to `ClientScenariosView` (Step 5)
8. **Records integration** — Scenario tags on rows, filter picker (Step 7)
9. **Deletion integration** — Clean up scenarios when deleting clients (Step 8)

---

## Testing

- Unit test scenario grouping logic (group by name, sort)
- Unit test scenario filter on records
- UI test: navigate to Scenarios tab, verify empty state
- UI test: navigate from client to `ClientScenariosView`
- Integration test (with stubbed CloudKit): toggle scenario → command created → record updated
