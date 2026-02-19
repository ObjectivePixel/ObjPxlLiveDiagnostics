import SwiftUI

enum SidebarAction: String, CaseIterable, Identifiable {
    case records = "Records"
    case scenarios = "Scenarios"
    case schema = "Schema"
    case debug = "Debug Info"
    case clients = "Clients"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .records:
            return "list.bullet.rectangle"
        case .scenarios:
            return "tag"
        case .schema:
            return "gear.badge.checkmark"
        case .debug:
            return "info.circle"
        case .clients:
            return "person.3"
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
                    .foregroundStyle(.secondary)
                Text(currentEnvironment)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(currentEnvironment.contains("Development") ? .blue : .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.1))
        }
    }
}
