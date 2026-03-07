import SwiftUI
import ObjPxlDiagnosticsShared

struct TelemetryClientsFilterView: View {
    @Binding var filter: ClientFilter

    var body: some View {
        Picker("Filter", selection: $filter) {
            ForEach(ClientFilter.allCases) { option in
                Text(option.rawValue)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
