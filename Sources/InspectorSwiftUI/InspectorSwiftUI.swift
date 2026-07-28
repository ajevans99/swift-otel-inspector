#if !os(watchOS)

import InspectorCore
import SwiftUI

/// A placeholder view used while the trace browser is assembled.
public struct InspectorPlaceholderView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.largeTitle)
            Text("No completed traces")
                .font(.headline)
            Text("Completed OpenTelemetry spans will appear here.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}


#endif
