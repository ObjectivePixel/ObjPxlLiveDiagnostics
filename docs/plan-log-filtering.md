# Plan: Log Filtering — Scenario + Log Level (Server-Side Predicate)

Converts the existing client-side scenario filter (from the `Port` commit) to use **server-side CloudKit predicate** queries, and adds a **log level filter** dropdown. Both filters can be used independently or combined (compound predicate), enabling:

- All logs at a specific level (e.g. "show me all diagnostic logs")
- All logs for a scenario (e.g. "show me everything from NetworkRequests")
- Logs for a scenario at a specific level (e.g. "show me diagnostic logs from NetworkRequests")

---

## Current State (after `Port` commit)

The scenario UI is already wired up:
- `TelemetryRecord.scenario: String?` field reads from `TelemetrySchema.Field.scenario`
- Scenario column in macOS `TelemetryTableView`, scenario tag in iOS `TelemetryRecordRowView`
- Scenario dropdown picker rendered in both `RecordsListMacView` and `RecordsListIOSView`
- `RecordsListView` owns `@State scenarioFilter: String?`, computes `filteredTelemetryRecords` client-side, derives `availableScenarios` from loaded records
- Static `filterRecords(_:byScenario:)` method with unit tests
- Package dependency already points to `claude/implement-scenario-spec-BkZf0`

**Not yet implemented:**
- Log level is not read from records or displayed anywhere in the viewer
- No log level dropdown
- Filtering is client-side only

**Package provides:**
- `TelemetrySchema.Field.logLevel` — indexed, queryable
- `TelemetryLogLevel` enum — `.info`, `.diagnostic` (String raw values, `CaseIterable`, `Comparable`)

---

## What Changes

### Step 1: Create `CloudKitClient+RecordFiltering.swift`

New extension on `CloudKitClient` adding a predicate-based fetch that accepts **both** optional filters. Builds a compound `NSPredicate` from whichever filters are active:

```swift
import CloudKit
import ObjPxlLiveTelemetry

extension CloudKitClient {
    func fetchRecords(
        scenario: String?,
        logLevel: String?,
        limit: Int,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        let operation: CKQueryOperation

        if let cursor {
            // Predicate is baked into the cursor — just paginate
            operation = CKQueryOperation(cursor: cursor)
        } else {
            var subpredicates: [NSPredicate] = []

            if let scenario {
                subpredicates.append(NSPredicate(
                    format: "%K == %@",
                    TelemetrySchema.Field.scenario.rawValue,
                    scenario
                ))
            }

            if let logLevel {
                subpredicates.append(NSPredicate(
                    format: "%K == %@",
                    TelemetrySchema.Field.logLevel.rawValue,
                    logLevel
                ))
            }

            let predicate = subpredicates.isEmpty
                ? NSPredicate(value: true)
                : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

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

Key design: a single method handles all four combinations (no filter, scenario only, log level only, both). `NSCompoundPredicate` ANDs together whichever sub-predicates are active.

### Step 2: Add `logLevel` field to `TelemetryRecord`

**File: `Views/TelemetryTableView.swift`**

```swift
struct TelemetryRecord: Identifiable {
    // ... existing fields ...
    let scenario: String?      // already exists
    let logLevel: String?      // NEW

    nonisolated init(_ record: CKRecord) {
        // ... existing ...
        scenario = record[TelemetrySchema.Field.scenario.rawValue] as? String
        logLevel = record[TelemetrySchema.Field.logLevel.rawValue] as? String   // NEW
    }
}
```

Add a "Log Level" `TableColumn` to the macOS Table:

```swift
TableColumn("Level") { record in
    if let logLevel = record.logLevel, !logLevel.isEmpty {
        Text(logLevel.capitalized)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(logLevel == "diagnostic" ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
            .clipShape(.rect(cornerRadius: 4))
    }
}
```

### Step 3: Move filter state to `ContentView`

`ContentView` owns the fetch logic, so both filters live here:

```swift
@State private var scenarioFilter: String? = nil
@State private var logLevelFilter: String? = nil
@State private var availableScenarios: [String] = []
```

- In `.task`, fetch scenario names via `cloudKitClient.fetchScenarios(forClient: nil)` → extract unique sorted `scenarioName` values
- Log level options come from `TelemetryLogLevel.allCases` (static, no fetch needed)
- Add `.onChange(of: scenarioFilter)` and `.onChange(of: logLevelFilter)` → re-fetch records
- Pass all filter state through `DetailView` → `RecordsListView`

### Step 4: Modify `ContentView.fetchRecords()` to use compound predicate

```swift
private func fetchRecords() async {
    guard let cloudKitClient else { return }
    // ...
    do {
        let result: ([CKRecord], CKQueryOperation.Cursor?)

        if scenarioFilter != nil || logLevelFilter != nil {
            result = try await cloudKitClient.fetchRecords(
                scenario: scenarioFilter,
                logLevel: logLevelFilter,
                limit: pageSize,
                cursor: nil
            )
        } else {
            result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: nil)
        }

        records = result.0
        nextCursor = result.1
    } catch { ... }
}
```

`loadMoreRecords()` needs no changes — cursor-based pagination already carries the predicate.

### Step 5: Update `DetailView` to thread filter params

Accept and pass through to `RecordsListView`:
- `scenarioFilter: Binding<String?>`
- `logLevelFilter: Binding<String?>`
- `availableScenarios: [String]`

### Step 6: Simplify `RecordsListView`

- Remove `@State private var scenarioFilter` (now received as binding from parent)
- Remove `filteredTelemetryRecords` computed property (server already filters)
- Remove `availableScenarios` computed property (now received from parent)
- Keep `filterRecords` static method for backward-compatible tests
- Accept filter bindings + scenario list as params
- Pass `telemetryRecords` directly (not filtered) to platform views
- Add `scenario` and `logLevel` to CSV export

### Step 7: Add log level dropdown to platform views

**macOS (`RecordsListMacView.swift`)** — add alongside existing scenario picker in header:

```swift
@Binding var logLevelFilter: String?

// In the header HStack:
Picker("Log Level", selection: $logLevelFilter) {
    Text("All Levels").tag(String?.none)
    ForEach(TelemetryLogLevel.allCases, id: \.rawValue) { level in
        Text(level.rawValue.capitalized).tag(String?.some(level.rawValue))
    }
}
.frame(maxWidth: 160)
```

**iOS (`RecordsListIOSView.swift`)** — add next to scenario picker:

```swift
@Binding var logLevelFilter: String?

// Adjacent to the scenario picker:
Picker("Log Level", selection: $logLevelFilter) {
    Text("All Levels").tag(String?.none)
    ForEach(TelemetryLogLevel.allCases, id: \.rawValue) { level in
        Text(level.rawValue.capitalized).tag(String?.some(level.rawValue))
    }
}
.pickerStyle(.menu)
```

### Step 8: Show log level on iOS record rows

**File: `TelemetryRecordRowView.swift`**

Add log level badge alongside existing device info:

```swift
if let logLevel = record.logLevel, !logLevel.isEmpty {
    Text(logLevel.capitalized)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(logLevel == "diagnostic" ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
        .clipShape(.rect(cornerRadius: 4))
}
```

### Step 9: Refresh scenario list on demand

Scenario names could change (new scenarios created). Refresh `availableScenarios` alongside record fetches.

---

## Filter Combinations

| Scenario | Log Level | Predicate | Result |
|----------|-----------|-----------|--------|
| nil | nil | `NSPredicate(value: true)` | All records (default) |
| "NetworkRequests" | nil | `scenario == "NetworkRequests"` | All logs for that scenario |
| nil | "diagnostic" | `logLevel == "diagnostic"` | All diagnostic logs |
| "NetworkRequests" | "diagnostic" | `scenario == "NetworkRequests" AND logLevel == "diagnostic"` | Diagnostic logs for that scenario |

---

## File Summary

### New Files

| File | Description |
|------|-------------|
| `CloudKitClient+RecordFiltering.swift` | Extension adding `fetchRecords(scenario:logLevel:limit:cursor:)` with compound server-side predicate |

### Modified Files

| File | Changes |
|------|---------|
| `Views/TelemetryTableView.swift` | Add `logLevel` field to `TelemetryRecord`; add Log Level column to macOS Table |
| `Views/ContentView.swift` | Add `scenarioFilter`, `logLevelFilter`, `availableScenarios` state; modify `fetchRecords()` to use compound predicate; `onChange` re-fetch for both filters; fetch scenario names on appear; pass filter params to DetailView |
| `Views/DetailView.swift` | Accept and pass `scenarioFilter` + `logLevelFilter` bindings and `availableScenarios` to `RecordsListView` |
| `Views/RecordsListView.swift` | Remove local filter state; accept filter params from parent; pass `telemetryRecords` directly; add `scenario` + `logLevel` to CSV export |
| `Views/RecordsListMacView.swift` | Add `logLevelFilter` binding; render log level dropdown in header |
| `Views/RecordsListIOSView.swift` | Add `logLevelFilter` binding; render log level dropdown |
| `Views/TelemetryRecordRowView.swift` | Show log level badge on each row |

### Unchanged Files

| File | Status |
|------|--------|
| `ScenarioFilterTests.swift` | Tests for `filterRecords` static method still valid |
| `ScenarioGroupingTests.swift` | Unrelated to record filtering |

---

## Implementation Order

1. **Create `CloudKitClient+RecordFiltering.swift`** (Step 1) — compound predicate extension
2. **Add `logLevel` to `TelemetryRecord` + macOS Table column** (Step 2)
3. **Move state + fetch logic to `ContentView`** (Steps 3–4)
4. **Thread through `DetailView`** (Step 5)
5. **Simplify `RecordsListView`** (Step 6)
6. **Add log level dropdown to macOS + iOS views** (Step 7)
7. **Show log level on iOS rows** (Step 8)
8. **Add `scenario` + `logLevel` to CSV** (part of Step 6)
9. **Verify tests still pass**
