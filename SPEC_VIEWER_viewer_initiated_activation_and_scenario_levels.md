# DiagnosticViewer Implementation Spec

## Overview

This change reworks how the viewer initiates client registration and how it controls per-scenario diagnostic levels. Instead of waiting for clients to self-register and then toggling enable/disable, the viewer operator enters a client code and sends an activation command. Scenario management changes from a binary toggle to a diagnostic level picker.

**No record ownership changes.** The client continues to own `TelemetryClient`, `TelemetryScenario`, and `TelemetryEvent` records. The viewer owns `TelemetryCommand` records.

---

## 1. TelemetryClientsView — Add Client flow

**File:** `Views/TelemetryClientsView.swift`

### 1a. New state variables

```swift
@State private var showAddClientSheet = false
@State private var addClientCode = ""
@State private var isSendingActivation = false
@State private var addClientError: String?
```

### 1b. Add Client button

Add a toolbar button following Apple HIG. On macOS, add to the header view. On iOS, add to the toolbar.

**macOS (TelemetryClientsHeaderView):** Add a "+" button or "Add Client" button in the header bar alongside the existing Refresh and Delete All buttons.

**iOS (TelemetryClientsToolbarView):** Add a toolbar item:

```swift
ToolbarItem(placement: .primaryAction) {
    Button("Add Client", systemImage: "plus") {
        showAddClientSheet = true
    }
}
```

### 1c. Add Client sheet/dialog

Present a sheet (iOS) or popover/sheet (macOS) when the button is tapped:

```swift
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
```

### 1d. AddClientView (new view)

**New file:** `Views/AddClientView.swift`

A simple form view:

```swift
struct AddClientView: View {
    @Binding var clientCode: String
    let isSending: Bool
    let errorMessage: String?
    let onSubmit: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client Code", text: $clientCode)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Enter the 12-character code displayed in the client app.")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Client")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Activate") {
                            Task { await onSubmit() }
                        }
                        .disabled(clientCode.trimmingCharacters(in: .whitespaces).count < 10)
                    }
                }
            }
        }
    }
}
```

Validation: The code should be at least 10 characters (the generator uses `max(10, length)` with default 12). Trim whitespace before submitting.

### 1e. `sendActivationCommand()` method

Add to `TelemetryClientsView`:

```swift
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

        // Success — dismiss sheet
        addClientCode = ""
        showAddClientSheet = false

        // Optionally fetch clients after a delay (client hasn't processed yet)
        // The subscription will notify us when the TelemetryClient record appears
    } catch {
        addClientError = "Failed to send activation command: \(error.localizedDescription)"
    }

    isSendingActivation = false
}
```

### 1f. Modify `toggleClientState()` — remove direct record update

The viewer cannot reliably update a client-owned `TelemetryClient` record. Remove the direct `updateTelemetryClient()` call. The viewer should only send a command and wait for the client to update its own record.

**Current code to change:**

```swift
private func toggleClientState(for clientRecord: TelemetryClientDisplay) async {
    // ... existing setup ...

    do {
        // Create command (KEEP)
        let commandAction: TelemetrySchema.CommandAction = targetState ? .enable : .disable
        let command = TelemetryCommandRecord(
            clientId: clientRecord.clientId,
            action: commandAction
        )
        let savedCommand = try await cloudKitClient.createCommand(command)

        // REMOVE: Direct record update
        // let updatedClient = TelemetryClientRecord(...)
        // let savedClient = try await cloudKitClient.updateTelemetryClient(updatedClient)

        // Instead: wait for client to process the command
        // The subscription will notify when the record changes
        await refreshClientStatus(for: clientRecord.id, expectedState: targetState)
    } catch {
        // ... error handling ...
    }
}
```

### 1g. Update empty state text

Change the empty state message from:
```swift
"No client records found. Clients will appear when they enable telemetry."
```
To:
```swift
"No clients registered. Tap + to add a client using their code."
```
(Adjust wording per platform — "Click" on macOS, "Tap" on iOS.)

### 1h. Delete All considerations

The `deleteAllClients()` method currently deletes client records and scenarios directly. Since the viewer doesn't own these records (the client does), these deletes may fail in production CloudKit. Two options:

1. **Remove "Delete All" from the viewer** — the viewer sends `.disable` commands and lets clients clean up.
2. **Keep it as a best-effort operation** — acknowledge it works in development but may not in production with default security roles.

Recommended: Change "Delete All" to send `.disable` commands to all active clients, rather than directly deleting records. Update the confirmation dialog text accordingly.

---

## 2. ScenariosView — Diagnostic level picker

**File:** `Views/ScenariosView.swift`

### 2a. Replace toggle with level picker

The `toggleScenario` function and its callers need to change from a boolean toggle to a diagnostic level selection.

Replace `toggleScenario(_:)` with `setScenarioLevel(_:level:)`:

```swift
private func setScenarioLevel(_ scenario: TelemetryScenarioRecord, level: Int) async {
    guard let cloudKitClient else { return }
    guard let recordID = scenario.recordID else {
        errorMessage = "Missing CloudKit record identifier for scenario."
        return
    }

    togglingScenarioID = recordID
    errorMessage = nil

    do {
        // Send setScenarioLevel command
        let command = TelemetryCommandRecord(
            clientId: scenario.clientId,
            action: .setScenarioLevel,
            scenarioName: scenario.scenarioName,
            diagnosticLevel: level
        )
        let savedCommand = try await cloudKitClient.createCommand(command)
        print("[Viewer] SetScenarioLevel command created: \(savedCommand.commandId)")

        // Note: Do NOT directly update the scenario record.
        // The client owns it and will update it when processing the command.
        // Wait for the change to propagate.
        await refreshScenarioLevel(for: recordID, expectedLevel: level)
    } catch {
        print("[Viewer] Failed to set scenario level: \(error)")
        errorMessage = error.localizedDescription
    }

    togglingScenarioID = nil
}
```

### 2b. Update `refreshScenarioStatus` → `refreshScenarioLevel`

```swift
private func refreshScenarioLevel(for id: CKRecord.ID, expectedLevel: Int) async {
    guard let cloudKitClient else { return }

    for _ in 0..<4 {
        do {
            let fetched = try await cloudKitClient.fetchScenarios(forClient: nil)
            let didUpdate = fetched.first(where: { $0.recordID == id })?.diagnosticLevel == expectedLevel

            scenarios = fetched

            if didUpdate {
                return
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        try? await Task.sleep(for: .seconds(0.5))
    }
}
```

### 2c. Pass level setter to ScenarioGroupView

Update the `ScenarioGroupView` call:

```swift
ScenarioGroupView(
    scenarioName: group.name,
    scenarios: group.scenarios,
    togglingScenarioID: togglingScenarioID,
    setScenarioLevel: setScenarioLevel     // was: toggleScenario
)
```

---

## 3. ScenarioGroupView — Level picker UI

**File:** `Views/ScenarioGroupView.swift`

### Update signature

```swift
struct ScenarioGroupView: View {
    let scenarioName: String
    let scenarios: [TelemetryScenarioRecord]
    let togglingScenarioID: CKRecord.ID?
    let setScenarioLevel: (TelemetryScenarioRecord, Int) async -> Void   // was: toggleScenario
    // ...
}
```

### Pass through to row view

```swift
ScenarioClientRowView(
    scenario: scenario,
    isToggling: togglingScenarioID == scenario.recordID,
    setLevel: { level in Task { await setScenarioLevel(scenario, level) } }
)
```

---

## 4. ScenarioClientRowView — Level picker

**File:** The row view used within `ScenarioGroupView` (likely in `ScenarioGroupView.swift` or a separate file).

### Replace toggle button with level Picker

Current UI: A button that toggles between Enable/Disable.

New UI: A `Picker` or `Menu` showing diagnostic levels.

```swift
struct ScenarioClientRowView: View {
    let scenario: TelemetryScenarioRecord
    let isToggling: Bool
    let setLevel: (Int) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(scenario.clientId)
                    .font(.headline)
                Text(scenario.created, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isToggling {
                ProgressView()
                    .controlSize(.small)
            } else {
                // Level indicator
                Text(levelLabel(for: scenario.diagnosticLevel))
                    .foregroundStyle(scenario.isActive ? .green : .secondary)

                // Level picker
                Menu {
                    Button("Off") { setLevel(TelemetryScenarioRecord.levelOff) }
                    Divider()
                    Button("Debug") { setLevel(TelemetryLogLevel.debug.rawValue) }
                    Button("Info") { setLevel(TelemetryLogLevel.info.rawValue) }
                    Button("Warning") { setLevel(TelemetryLogLevel.warning.rawValue) }
                    Button("Error") { setLevel(TelemetryLogLevel.error.rawValue) }
                } label: {
                    Label("Level", systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)   // macOS
            }
        }
    }

    private func levelLabel(for level: Int) -> String {
        if level < 0 { return "Off" }
        return TelemetryLogLevel(rawValue: level)?.description ?? "Unknown"
    }
}
```

Alternative: Use a `Picker` with `.menu` style for a more compact inline presentation:

```swift
Picker("Level", selection: levelBinding) {
    Text("Off").tag(TelemetryScenarioRecord.levelOff)
    Text("Debug").tag(TelemetryLogLevel.debug.rawValue)
    Text("Info").tag(TelemetryLogLevel.info.rawValue)
    Text("Warning").tag(TelemetryLogLevel.warning.rawValue)
    Text("Error").tag(TelemetryLogLevel.error.rawValue)
}
.pickerStyle(.menu)
```

Where `levelBinding` is a `Binding<Int>` that calls `setLevel` on change.

---

## 5. ClientScenariosView — Same level picker changes

**File:** `Views/ClientScenariosView.swift`

Apply the same changes as ScenariosView:

### 5a. Replace `toggleScenario` with `setScenarioLevel`

```swift
private func setScenarioLevel(_ scenario: TelemetryScenarioRecord, level: Int) async {
    guard let cloudKitClient else { return }
    guard let recordID = scenario.recordID else {
        errorMessage = "Missing CloudKit record identifier for scenario."
        return
    }

    togglingScenarioID = recordID
    errorMessage = nil

    do {
        let command = TelemetryCommandRecord(
            clientId: client.clientId,
            action: .setScenarioLevel,
            scenarioName: scenario.scenarioName,
            diagnosticLevel: level
        )
        _ = try await cloudKitClient.createCommand(command)

        // Do NOT update scenario record directly (client owns it)
        // Refresh to pick up client's update
        await refreshAfterLevelChange(for: recordID, expectedLevel: level)
    } catch {
        errorMessage = error.localizedDescription
    }

    togglingScenarioID = nil
}
```

### 5b. Replace row UI

Replace the toggle button in the List row with the same `Menu`-based level picker described in section 4.

### 5c. Update status display

Replace:
```swift
Label(
    scenario.isEnabled ? "Active" : "Inactive",
    systemImage: scenario.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
)
.foregroundStyle(scenario.isEnabled ? .green : .orange)
```

With:
```swift
Label(
    scenario.isActive ? levelLabel(for: scenario.diagnosticLevel) : "Off",
    systemImage: scenario.isActive ? "checkmark.circle.fill" : "pause.circle.fill"
)
.foregroundStyle(scenario.isActive ? .green : .secondary)
```

---

## 6. TelemetryClientsView macOS Table — Scenario level in table

**File:** `Views/TelemetryClientsView.swift`

### Update Scenarios column

The Scenarios column currently shows a count. No change needed here — it still shows the count of registered scenarios. The level detail is visible when drilling into the client's scenarios.

### Update Actions column (if deactivating)

When deactivating, the viewer sends a `.disable` command only (no direct record update):

```swift
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
```

For the "Activate" action on an existing-but-disabled client, the viewer sends an `.enable` command (not `.activate`, since the record already exists). The `.activate` command is only for initial registration via the Add Client flow.

---

## 7. Model imports

Since `TelemetryScenarioRecord` and `TelemetryCommandRecord` are defined in the `ObjPxlLiveTelemetry` module (client library), the viewer already imports this. The new fields (`diagnosticLevel`, `isActive`, `resolvedLevel`) and types (`TelemetryLogLevel` with new cases) will be available automatically.

Ensure the viewer's `import ObjPxlLiveTelemetry` picks up the updated models. No new imports needed.

---

## 8. Schema View updates (if applicable)

If the viewer has a schema inspection view that displays field metadata, update it to reflect:
- `TelemetryScenario.diagnosticLevel` (Int64) replacing `isEnabled`
- `TelemetryCommand.diagnosticLevel` (Int64) new field
- `TelemetryEvent.logLevel` changing from String to Int64

---

## 9. Removed functionality

| Removed | Replacement |
|---|---|
| Direct `updateTelemetryClient()` in toggleClientState | Command-only approach; viewer sends command, client updates its own record |
| Direct `updateScenario()` in toggle/set functions | Command-only approach; viewer sends command, client updates its own record |
| Binary Enable/Disable buttons on scenarios | Diagnostic level picker (Off / Debug / Info / Warning / Error) |
| `enableScenario` / `disableScenario` commands | `setScenarioLevel` command with `diagnosticLevel` field |
| Implicit client registration (waiting for clients to appear) | Explicit "Add Client" flow with code entry |

---

## 10. New files

| File | Purpose |
|---|---|
| `Views/AddClientView.swift` | Sheet/dialog for entering client code and sending activation command |

---

## 11. Files changed (summary)

| File | Change type |
|---|---|
| `Views/TelemetryClientsView.swift` | Modify (add client flow, remove direct record updates) |
| `Views/TelemetryClientsHeaderView.swift` | Modify (add "Add Client" button — macOS) |
| `Views/TelemetryClientsToolbarView.swift` | Modify (add "Add Client" button — iOS) |
| `Views/TelemetryClientsListView.swift` | Minor (empty state text) |
| `Views/ScenariosView.swift` | Modify (level picker, remove toggle) |
| `Views/ClientScenariosView.swift` | Modify (level picker, remove toggle, remove direct record update) |
| `Views/ScenarioGroupView.swift` | Modify (pass level setter instead of toggle) |
| `Views/AddClientView.swift` | **New file** |

---

## 12. Interaction diagram

```
Viewer                          CloudKit                        Client
  |                                |                               |
  |-- [Operator enters code] ---->|                               |
  |   Create TelemetryCommand     |                               |
  |   (action: .activate,         |                               |
  |    clientId: "abc123...")      |                               |
  |                                |                               |
  |                                |     [User taps "Request       |
  |                                |      Diagnostics"]            |
  |                                |<--- Poll pending commands ----|
  |                                |---- Return .activate cmd ---->|
  |                                |                               |
  |                                |<--- Create TelemetryClient ---|
  |                                |<--- Create TelemetryScenarios-|
  |                                |<--- Setup cmd subscription ---|
  |                                |---- Mark cmd executed ------->|
  |                                |                               |
  |<-- Subscription notification --|                               |
  |   (TelemetryClient-All)        |                               |
  |-- Refresh client list -------->|                               |
  |<-- Client now visible ---------|                               |
  |                                |                               |
  |-- [Operator sets level] ----->|                               |
  |   Create TelemetryCommand     |                               |
  |   (action: .setScenarioLevel,  |                               |
  |    scenarioName: "...",        |                               |
  |    diagnosticLevel: 1)         |                               |
  |                                |---- Push notification ------->|
  |                                |<--- Update scenario record ---|
  |                                |<--- Mark cmd executed --------|
  |                                |                               |
  |-- [Operator deactivates] ---->|                               |
  |   Create TelemetryCommand     |                               |
  |   (action: .disable)           |                               |
  |                                |---- Push notification ------->|
  |                                |<--- Delete TelemetryClient ---|
  |                                |<--- Delete scenarios, events -|
  |<-- Subscription notification --|                               |
  |   (TelemetryClient-All)        |                               |
  |-- Refresh: client gone ------->|                               |
```
