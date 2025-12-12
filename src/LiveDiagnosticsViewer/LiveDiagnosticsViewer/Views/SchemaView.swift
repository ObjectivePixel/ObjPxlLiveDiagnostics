import SwiftUI

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
                                .foregroundStyle(.blue)
                                .help("Queryable/Indexed")
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))

            Text("Client Record Type: \(TelemetrySchema.clientRecordType)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(TelemetrySchema.ClientField.allCases, id: \.rawValue) { field in
                    HStack {
                        Text(field.rawValue)
                            .font(.monospaced(.body)())
                        Spacer()
                        if field.isIndexed {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.blue)
                                .help("Queryable/Indexed")
                        }
                        Text(field.fieldTypeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(.rect(cornerRadius: 8))

            Spacer()
        }
        .padding()
        .navigationTitle("Schema")
    }
}
