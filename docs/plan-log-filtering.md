# Plan: Scenario Filter for Logs Tab — Server-Side Predicate

Converts the existing client-side scenario filter (from the `Port` commit) to use a **server-side CloudKit predicate** query so only matching records are fetched from the database.

---

## Current State (after `Port` commit)

The scenario UI is already wired up:
- `TelemetryRecord.scenario: String?` field reads from `TelemetrySchema.Field.scenario`
- Scenario column in macOS `TelemetryTableView`, scenario tag in iOS `TelemetryRecordRowView`
- Scenario dropdown picker rendered in both `RecordsListMacView` and `RecordsListIOSView`
- `RecordsListView` owns `@State scenarioFilter: String?`, computes `filteredTelemetryRecords` client-side, derives `availableScenarios` from loaded records
- Static `filterRecords(_:byScenario:)` method with unit tests
- Package dependency already points to `claude/implement-scenario-spec-BkZf0`

**Problem**: Filtering is client-side — all records are fetched, then filtered in memory. With many records this is wasteful. The `scenario` field is indexed in CloudKit, so predicate queries are efficient.

**Second problem**: `availableScenarios` is derived from loaded records. Once we filter server-side, the loaded set only contains the selected scenario's records, so the dropdown would lose its other options.

---

## What Changes

### Step 1: Create `CloudKitClient+RecordFiltering.swift`

New extension on `CloudKitClient` adding a predicate-based fetch. The package's `fetchRecords(limit:cursor:)` doesn't accept a predicate, so we extend locally:

```swift
extension CloudKitClient {
    func fetchRecords(
        scenario: String,
        limit: Int,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        // When cursor exists, predicate is baked in — just paginate
        // When no cursor, build CKQuery with NSPredicate(format: "scenario == %@", scenario)
        // Same CKQueryOperation pattern as existing fetchRecords
    }
}
```

### Step 2: Move filter state to `ContentView`

`ContentView` owns the fetch logic, so `scenarioFilter` and `availableScenarios` need to live there:

- Add `@State private var scenarioFilter: String? = nil`
- Add `@State private var availableScenarios: [String] = []`
- In `.task`, fetch scenario names via `cloudKitClient.fetchScenarios(forClient: nil)` → extract unique sorted `scenarioName` values
- Add `.onChange(of: scenarioFilter)` → re-fetch records
- Pass `scenarioFilter` binding + `availableScenarios` through `DetailView` → `RecordsListView`

### Step 3: Modify `ContentView.fetchRecords()` to use predicate

```swift
private func fetchRecords() async {
    // ...
    if let scenario = scenarioFilter {
        let result = try await cloudKitClient.fetchRecords(
            scenario: scenario, limit: pageSize, cursor: nil
        )
        // ...
    } else {
        let result = try await cloudKitClient.fetchRecords(limit: pageSize, cursor: nil)
        // ...
    }
}
```

`loadMoreRecords()` needs no changes — cursor-based pagination already carries the predicate.

### Step 4: Update `DetailView` to thread filter params

Accept and pass `scenarioFilter: Binding<String?>` and `availableScenarios: [String]` to `RecordsListView`.

### Step 5: Simplify `RecordsListView`

- Remove `@State private var scenarioFilter` (now received as binding from parent)
- Remove `filteredTelemetryRecords` computed property (server already filters)
- Remove `availableScenarios` computed property (now received from parent)
- Keep `filterRecords` static method for backward-compatible tests
- Accept `scenarioFilter: Binding<String?>` and `availableScenarios: [String]` as params
- Pass `telemetryRecords` directly (not filtered) to platform views

### Step 6: Update platform views

`RecordsListMacView` and `RecordsListIOSView` already accept `@Binding var scenarioFilter` and `let availableScenarios` — no interface changes needed. Just verify they still compile after `RecordsListView` changes.

### Step 7: Add `scenario` to CSV export

Update `copySelected()` in `RecordsListView` to include scenario in the CSV header and row data.

### Step 8: Refresh scenario list on demand

Scenario names could change (new scenarios created). Refresh `availableScenarios` alongside record fetches — either on every fetch, or on a separate cadence.

---

## File Summary

### New Files

| File | Description |
|------|-------------|
| `CloudKitClient+RecordFiltering.swift` | Extension adding `fetchRecords(scenario:limit:cursor:)` with server-side predicate |

### Modified Files

| File | Changes |
|------|---------|
| `Views/ContentView.swift` | Add `scenarioFilter`, `availableScenarios` state; modify `fetchRecords()` to branch on filter; add `onChange` re-fetch; fetch scenario names on appear; pass filter params to DetailView |
| `Views/DetailView.swift` | Accept and pass `scenarioFilter` binding + `availableScenarios` to `RecordsListView` |
| `Views/RecordsListView.swift` | Remove local filter state; accept filter params from parent; pass `telemetryRecords` directly; add scenario to CSV export |

### Unchanged Files (already correct from Port commit)

| File | Status |
|------|--------|
| `Views/TelemetryTableView.swift` | `scenario` field + table column already done |
| `Views/RecordsListMacView.swift` | Dropdown already wired |
| `Views/RecordsListIOSView.swift` | Dropdown already wired |
| `Views/TelemetryRecordRowView.swift` | Scenario tag already shown |
| `ScenarioFilterTests.swift` | Tests for `filterRecords` still valid |

---

## Implementation Order

1. **Create `CloudKitClient+RecordFiltering.swift`** (Step 1)
2. **Move state + fetch logic to `ContentView`** (Steps 2–3)
3. **Thread through `DetailView`** (Step 4)
4. **Simplify `RecordsListView`** (Step 5)
5. **Verify platform views compile** (Step 6)
6. **Add scenario to CSV** (Step 7)
7. **Verify tests still pass** — existing `ScenarioFilterTests` test the static method which stays
