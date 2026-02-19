# Plan: Scenario Filter for Logs Tab

Adds a **scenario dropdown filter** to the Records (logs) tab that uses a **server-side CloudKit predicate** to fetch only records matching the selected scenario. Dropdown-based UI rather than hierarchical list since there may be many log records.

**Prerequisites**: Update the `ObjPxlLiveTelemetry` package reference to point to `claude/implement-scenario-spec-BkZf0` which adds `TelemetrySchema.Field.scenario`, `TelemetryScenarioRecord`, `ScenarioField`, and scenario CRUD methods.

---

## Context

The Records tab currently shows a flat list of all fetched telemetry records with no filtering. The updated client package adds a `scenario` field to `TelemetrySchema.Field` (indexed/queryable), meaning TelemetryEvent records in CloudKit can carry a scenario name. We want to let the user select a scenario from a dropdown and re-query CloudKit with a predicate so only matching records are returned.

### What the user sees today

- **Records tab**: Fetch button → flat table/list of all records, sorted by timestamp. No filtering.

### What the user will see after this change

- **Records tab**: A **Scenario** dropdown picker in the header/toolbar area.
  - Default: "All Scenarios" (no filter — fetches all records as today)
  - Options populated from `TelemetryScenarioRecord`s fetched from CloudKit
  - Selecting a scenario triggers a new server-side fetch with `scenario == selectedName` predicate
  - Record count updates to reflect filtered results

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Filter UI | `Picker` with `.menu` style (dropdown) | Compact, scales to many scenarios, user requested dropdowns |
| Filter location (macOS) | Header `HStack` next to Fetch/Copy/Clear buttons | Matches `TelemetryClientsHeaderView` pattern |
| Filter location (iOS) | Above the list, below the toolbar | Consistent with existing filter patterns |
| Scenario list source | Fetched via `cloudKitClient.fetchScenarios(forClient: nil)` | Gets all known scenario names from `TelemetryScenario` records — authoritative, doesn't depend on which event records happen to be loaded |
| Filter execution | **Server-side CloudKit predicate** | Reduces data transfer; the `scenario` field is indexed so queries are efficient |
| Implementation | Local extension on `CloudKitClient` for predicate-based record fetch | The package's `fetchRecords(limit:cursor:)` doesn't accept a predicate, so we extend it locally with a `scenario` parameter |

---

## Step 1: Update Package Dependency

Update `Package.resolved` to point to the `claude/implement-scenario-spec-BkZf0` branch of `LiveDiagnosticsClient`, which provides:

- `TelemetrySchema.Field.scenario` (indexed, queryable)
- `TelemetrySchema.ScenarioField` enum
- `TelemetryScenarioRecord` struct
- `CloudKitClientProtocol.fetchScenarios(forClient:)` method

---

## Step 2: Add `scenario` field to `TelemetryRecord`

### File: `Views/TelemetryTableView.swift`

Add field to the local view-layer struct:

```swift
struct TelemetryRecord: Identifiable {
    // ... existing fields ...
    let scenario: String       // NEW
    // ...

    nonisolated init(_ record: CKRecord) {
        // ... existing fields ...
        scenario = record[TelemetrySchema.Field.scenario.rawValue] as? String ?? ""
    }
}
```

---

## Step 3: Create local extension for predicate-based record fetch

### New file: `CloudKitClient+RecordFiltering.swift`

Extension on `CloudKitClient` that queries `TelemetryEvent` records with a scenario predicate. Uses the same `CKQueryOperation` pattern as the existing `fetchRecords` but adds a predicate:

```swift
import CloudKit
import ObjPxlLiveTelemetry

extension CloudKitClient {
    func fetchRecords(
        scenario: String,
        limit: Int,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        let operation: CKQueryOperation

        if let cursor {
            operation = CKQueryOperation(cursor: cursor)
        } else {
            let predicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.Field.scenario.rawValue,
                scenario
            )
            let query = CKQuery(
                recordType: TelemetrySchema.recordType,
                predicate: predicate
            )
            query.sortDescriptors = [
                NSSortDescriptor(
                    key: TelemetrySchema.Field.eventTimestamp.rawValue,
                    ascending: false
                )
            ]
            operation = CKQueryOperation(query: query)
        }

        operation.resultsLimit = limit
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var pageRecords: [CKRecord] = []

            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    pageRecords.append(record)
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (pageRecords, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }
}
```

Key: when `cursor` is provided, the predicate is already baked into the cursor, so we don't re-specify it. This matches the existing `fetchRecords` pattern.

---

## Step 4: Wire scenario filter into `ContentView`

### File: `ContentView.swift`

`ContentView` owns the record-fetching logic. Add scenario filter state and use the filtered fetch:

```swift
@State private var scenarioFilter: String? = nil    // nil = all
@State private var availableScenarios: [String] = []
```

On `.task`, fetch available scenario names:
```swift
let scenarios = try await cloudKitClient.fetchScenarios(forClient: nil)
availableScenarios = Set(scenarios.map(\.scenarioName)).sorted()
```

Modify `fetchRecords()` to use the scenario predicate when a filter is active:
```swift
if let scenario = scenarioFilter {
    let result = try await cloudKitClient.fetchRecords(
        scenario: scenario,
        limit: pageSize,
        cursor: nil
    )
    // ...
} else {
    let result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: nil)
    // ...
}
```

Same for `loadMoreRecords()` — it already uses the cursor, which carries the predicate.

When `scenarioFilter` changes, re-fetch:
```swift
.onChange(of: scenarioFilter) { _, _ in
    Task { await fetchRecords() }
}
```

Pass `scenarioFilter`, `availableScenarios` down through `DetailView` → `RecordsListView`.

---

## Step 5: Thread filter state through the view hierarchy

### File: `DetailView.swift`

Accept and pass through `scenarioFilter: Binding<String?>` and `availableScenarios: [String]` to `RecordsListView`.

### File: `RecordsListView.swift`

Accept `scenarioFilter: Binding<String?>` and `availableScenarios: [String]` as parameters. Pass them down to the platform-specific views.

Update CSV export to include a `scenario` column.

---

## Step 6: Add scenario dropdown to macOS view

### File: `Views/RecordsListMacView.swift`

Add parameters and render the dropdown in the header:

```swift
@Binding var scenarioFilter: String?
let availableScenarios: [String]

// In the header HStack, after the existing buttons:
Picker("Scenario", selection: $scenarioFilter) {
    Text("All Scenarios").tag(String?.none)
    ForEach(availableScenarios, id: \.self) { name in
        Text(name).tag(String?.some(name))
    }
}
.pickerStyle(.menu)
```

Also add a "Scenario" `TableColumn` to `TelemetryTableView`:
```swift
TableColumn("Scenario", value: \.scenario) { record in
    if !record.scenario.isEmpty {
        Label(record.scenario, systemImage: "tag")
            .font(.caption)
    }
}
```

---

## Step 7: Add scenario dropdown to iOS view

### File: `Views/RecordsListIOSView.swift`

Same parameters. Render the dropdown above the list content:

```swift
@Binding var scenarioFilter: String?
let availableScenarios: [String]

// Above the content:
if !availableScenarios.isEmpty {
    Picker("Scenario", selection: $scenarioFilter) {
        Text("All Scenarios").tag(String?.none)
        ForEach(availableScenarios, id: \.self) { name in
            Text(name).tag(String?.some(name))
        }
    }
    .pickerStyle(.menu)
    .padding(.horizontal)
}
```

Show scenario on each row in `TelemetryRecordRowView`:
```swift
if !record.scenario.isEmpty {
    Label(record.scenario, systemImage: "tag")
        .font(.caption)
        .foregroundStyle(.tint)
}
```

---

## File Summary

### New Files

| File | Description |
|------|-------------|
| `CloudKitClient+RecordFiltering.swift` | Extension adding `fetchRecords(scenario:limit:cursor:)` with server-side predicate |

### Modified Files

| File | Changes |
|------|---------|
| `Package.resolved` | Update to `claude/implement-scenario-spec-BkZf0` branch |
| `Views/TelemetryTableView.swift` | Add `scenario` field to `TelemetryRecord`; add Scenario column to macOS Table |
| `Views/ContentView.swift` | Add `scenarioFilter` and `availableScenarios` state; modify `fetchRecords()` to apply predicate; fetch scenario list on appear; re-fetch on filter change |
| `Views/DetailView.swift` | Thread `scenarioFilter` binding and `availableScenarios` through to `RecordsListView` |
| `Views/RecordsListView.swift` | Accept scenario filter params; pass to platform views; update CSV export |
| `Views/RecordsListMacView.swift` | Add scenario dropdown to header; pass to table |
| `Views/RecordsListIOSView.swift` | Add scenario dropdown above list |
| `Views/TelemetryRecordRowView.swift` | Show scenario tag on each row |

---

## Implementation Order

1. **Update package dependency** (Step 1) — prerequisite for all type access
2. **Add `scenario` to `TelemetryRecord`** (Step 2) — data model change
3. **Create record filtering extension** (Step 3) — server-side query capability
4. **Wire filter into `ContentView`** (Step 4) — state + fetch logic
5. **Thread through view hierarchy** (Step 5) — `DetailView` → `RecordsListView`
6. **macOS dropdown + table column** (Step 6) — UI
7. **iOS dropdown + row display** (Step 7) — UI
