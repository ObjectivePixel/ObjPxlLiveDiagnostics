import SwiftUI

public struct DiagnosticsView: View {
    private let cloudKitClient: CloudKitClient

    public init(containerIdentifier: String) {
        cloudKitClient = CloudKitClient(containerIdentifier: containerIdentifier)
    }

    public var body: some View {
        ContentView()
            .environment(\.cloudKitClient, cloudKitClient)
    }
}
