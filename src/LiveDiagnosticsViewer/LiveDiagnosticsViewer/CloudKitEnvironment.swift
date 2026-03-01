import ObjPxlLiveTelemetry
import SwiftUI

private struct CloudKitClientKey: EnvironmentKey {
    static let defaultValue: CloudKitClient? = nil
}

extension EnvironmentValues {
    var cloudKitClient: CloudKitClient? {
        get { self[CloudKitClientKey.self] }
        set { self[CloudKitClientKey.self] = newValue }
    }
}
