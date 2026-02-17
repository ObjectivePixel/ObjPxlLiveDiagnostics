# Plan: Log Filtering by Client and Scenario

Adds dropdown-based filtering to the Records (logs) tab so users can narrow records by **Client** and **Scenario**. Uses dropdowns rather than hierarchical lists since there may be many log records.

**Prerequisites**: The `TelemetryRecord` struct needs a `clientId` field (currently absent). If the scenario feature from `plan-scenario-logging-viewer.md` has landed, a `scenario` field is also needed. This plan can be implemented in two passes — client filtering first (available now), scenario filtering once scenarios exist.

---

## Context

Currently the Records tab shows a flat list of all fetched telemetry records with no filtering. The Clients tab already has a working `ClientFilter` (All/Active/Inactive) using a segmented `Picker`. We'll follow the same pattern — client-side filtering over the already-fetched data set — using dropdown `Picker`s in the toolbar/header area.

### What the user sees today

- **Records tab**: Fetch button → flat table/list of all records, sorted by timestamp. No way to narrow by client or scenario.
- **Clients tab**: Segmented filter (All/Active/Inactive), but this only filters the client list itself — not logs.

### What the user will see after this change

- **Records tab**: One or two dropdown pickers in the header/toolbar area:
  1. **Client** dropdown — "All Clients" plus each unique `clientId` found in the current record set
  2. **Scenario** dropdown — "All Scenarios" plus each unique scenario name (once scenario fields exist)
- Filtering is applied client-side to the already-fetched `[TelemetryRecord]` array
- Record count in the nav title updates to reflect the filtered count
- Filters reset when records are re-fetched

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Filter UI widget | `Picker` with `.menu` style (dropdown) | Scales to many values without taking screen space; matches the user's request for "dropdowns rather than a hierarchical list" |
| Filter location (macOS) | In the header `HStack` next to Fetch/Copy/Clear buttons | Consistent with `TelemetryClientsHeaderView` pattern |
| Filter location (iOS) | Above the list, below the navigation bar | Consistent with `TelemetryClientsFilterView` pattern; toolbar is already full with action buttons |
| Data source for filter options | Derived from current in-memory `[TelemetryRecord]` | No extra CloudKit fetch needed; options update automatically when records are fetched/paginated |
| Filter execution | Client-side computed property | Same pattern as `TelemetryClientsView.filteredClients`; records are already loaded (max 200 per page, paginated) |
| Scenario filter availability | Only shown when scenario data exists in records | Graceful degradation — if no records have a scenario field populated, the dropdown is hidden |

---

## Step 1: Add `clientId` (and `scenario`) to `TelemetryRecord`

### File: `Views/TelemetryTableView.swift`

Add fields to the `TelemetryRecord` struct:

```swift
struct TelemetryRecord: Identifiable {
    // ... existing fields ...
    let clientId: String       // NEW — from TelemetrySchema.Field.clientId or similar
    let scenario: String       // NEW — from scenario field, defaults to "" if not present
    // ...
}
```

In the `init(_ record: CKRecord)`:

```swift
clientId = record["clientId"] as? String ?? "Unknown"
scenario = record["scenario"] as? String ?? ""
```

> **Note**: Need to verify the exact CloudKit field name for clientId. It may be stored under `TelemetrySchema.ClientField` or similar. If no `clientId` field exists on telemetry records in CloudKit, we'll need to use `deviceName` or another device-identifying field as a proxy for "client". The `deviceName` field already exists and is populated — this may be the practical identifier until a proper `clientId` is added to telemetry event records.

---

## Step 2: Create `RecordsFilterView` (shared filter bar component)

### New file: `Views/RecordsFilterView.swift`

A reusable filter bar containing the dropdown pickers. Used by both iOS and macOS record views.

```swift
struct RecordsFilterView: View {
    @Binding var clientFilter: String?     // nil = "All Clients"
    @Binding var scenarioFilter: String?   // nil = "All Scenarios"
    let availableClients: [String]         // sorted unique client IDs
    let availableScenarios: [String]       // sorted unique scenario names

    var body: some View {
        HStack(spacing: 12) {
            Picker("Client", selection: $clientFilter) {
                Text("All Clients").tag(String?.none)
                ForEach(availableClients, id: \.self) { client in
                    Text(client).tag(String?.some(client))
                }
            }
            .pickerStyle(.menu)

            if !availableScenarios.isEmpty {
                Picker("Scenario", selection: $scenarioFilter) {
                    Text("All Scenarios").tag(String?.none)
                    ForEach(availableScenarios, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
```

Key behaviors:
- Scenario picker is conditionally shown (only when records contain scenario data)
- Uses `.menu` picker style for compact dropdowns
- Labels show the current selection in the dropdown button

---

## Step 3: Add filter state and logic to `RecordsListView`

### File: `Views/RecordsListView.swift`

Add `@State` for filters and computed properties for available options and filtered records:

```swift
@State private var clientFilter: String? = nil
@State private var scenarioFilter: String? = nil

private var availableClients: [String] {
    Set(telemetryRecords.map(\.clientId)).sorted()
}

private var availableScenarios: [String] {
    Set(telemetryRecords.map(\.scenario).filter { !$0.isEmpty }).sorted()
}

private var filteredRecords: [TelemetryRecord] {
    telemetryRecords.filter { record in
        if let clientFilter, record.clientId != clientFilter {
            return false
        }
        if let scenarioFilter, record.scenario != scenarioFilter {
            return false
        }
        return true
    }
}
```

Pass `filteredRecords` (instead of `telemetryRecords`) down to the platform-specific views. Also pass the filter bindings and available options down for rendering the filter bar.

Update `copySelected()` CSV header and row mapping to include `clientId` and `scenario` columns.

Reset filters when records change significantly (new fetch):
```swift
.onChange(of: records.count) { _, _ in
    clientFilter = nil
    scenarioFilter = nil
}
```

---

## Step 4: Integrate filter bar into macOS view

### File: `Views/RecordsListMacView.swift`

Add parameters for filter state and render `RecordsFilterView` in the header `HStack`:

```swift
struct RecordsListMacView: View {
    // ... existing params ...
    @Binding var clientFilter: String?
    @Binding var scenarioFilter: String?
    let availableClients: [String]
    let availableScenarios: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // existing buttons: Fetch Records, Copy Selected, Clear All, ProgressView
                // ...

                Spacer()  // push filters to the right

                RecordsFilterView(
                    clientFilter: $clientFilter,
                    scenarioFilter: $scenarioFilter,
                    availableClients: availableClients,
                    availableScenarios: availableScenarios
                )
            }
            // ... rest of view unchanged
        }
    }
}
```

Also add a "Scenario" `TableColumn` to `TelemetryTableView` (conditionally, or always — showing empty for records without a scenario).

Update the nav title to show filtered count vs total:
```swift
.navigationTitle("Telemetry Records (\(telemetryRecords.count) of \(totalCount))")
// or just show filtered count
```

---

## Step 5: Integrate filter bar into iOS view

### File: `Views/RecordsListIOSView.swift`

Add the same filter parameters and render `RecordsFilterView` above the list:

```swift
struct RecordsListIOSView: View {
    // ... existing params ...
    @Binding var clientFilter: String?
    @Binding var scenarioFilter: String?
    let availableClients: [String]
    let availableScenarios: [String]

    var body: some View {
        VStack(alignment: .leading) {
            RecordsFilterView(
                clientFilter: $clientFilter,
                scenarioFilter: $scenarioFilter,
                availableClients: availableClients,
                availableScenarios: availableScenarios
            )
            .padding(.horizontal)

            // ... existing content (loading, empty, list) ...
        }
    }
}
```

Optionally show `clientId` and `scenario` in `TelemetryRecordRowView` — e.g., a `Label(record.clientId, systemImage: "person")` caption below the existing device info row, and a scenario tag badge.

---

## Step 6: Update record count display

Both platforms should reflect filtered counts:

- **macOS** (`RecordsListMacView`): Navigation title shows `"Telemetry Records (showing X of Y)"` when a filter is active, or `"Telemetry Records (Y)"` when unfiltered.
- **iOS** (`RecordsListIOSView`): Same pattern in `.navigationTitle`.

---

## File Summary

### New Files

| File | Description |
|------|-------------|
| `Views/RecordsFilterView.swift` | Shared dropdown filter bar with Client and Scenario pickers |

### Modified Files

| File | Changes |
|------|---------|
| `Views/TelemetryTableView.swift` | Add `clientId` and `scenario` fields to `TelemetryRecord`; optionally add Scenario column to macOS Table |
| `Views/RecordsListView.swift` | Add filter `@State`, computed `filteredRecords`/`availableClients`/`availableScenarios`, pass filtered data + bindings to platform views, update CSV export |
| `Views/RecordsListMacView.swift` | Accept filter bindings + options, render `RecordsFilterView` in header, update nav title for filtered count |
| `Views/RecordsListIOSView.swift` | Accept filter bindings + options, render `RecordsFilterView` above list, update nav title for filtered count |
| `Views/TelemetryRecordRowView.swift` | Optionally display `clientId` in the row (helps identify which client a log belongs to even without filtering) |

---

## Implementation Order

1. **Add fields to `TelemetryRecord`** (Step 1) — prerequisite for everything else
2. **Create `RecordsFilterView`** (Step 2) — standalone component, no dependencies
3. **Add filter logic to `RecordsListView`** (Step 3) — wire up state and computed properties
4. **Integrate into macOS view** (Step 4) — render filter bar, pass filtered data
5. **Integrate into iOS view** (Step 5) — render filter bar, pass filtered data
6. **Update record counts** (Step 6) — polish nav titles

---

## Open Questions

1. **What CloudKit field name holds the client identifier on telemetry event records?** The `TelemetryRecord` struct currently has no `clientId`. If event records don't store a client ID, we could use `deviceName` as a client proxy, or this would require a schema change in the `ObjPxlLiveTelemetry` package to start writing `clientId` onto each telemetry event record.

2. **Is the scenario field already present on telemetry event `CKRecord`s?** The existing plan (`plan-scenario-logging-viewer.md`) calls for adding `TelemetrySchema.Field.scenario`, but this hasn't been implemented yet. The scenario filter should be built to gracefully hide itself when no scenario data is present.

3. **Should filtering also trigger a server-side CloudKit query?** Current approach is client-side only (filter the already-fetched 200+ records). For very large data sets, a server-side predicate filter could reduce transfer, but adds complexity and latency. Recommendation: start client-side, add server-side later if needed.
