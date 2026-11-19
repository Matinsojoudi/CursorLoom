import SwiftUI
import ApplicationServices

@main
struct InputBridgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 480, minHeight: 300)
        }
    }
}

struct ContentView: View {
    @State private var isTrusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("InputBridge").font(.largeTitle.bold())
            Text("Work in progress").font(.headline)
            Text("Remote control is disabled until an authenticated, encrypted connection is implemented.")
            Divider()
            Label(isTrusted ? "Accessibility permission granted" : "Accessibility permission not granted",
                  systemImage: isTrusted ? "checkmark.shield" : "exclamationmark.shield")
            HStack {
                Button("Request Accessibility Permission") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    isTrusted = AXIsProcessTrusted()
                }
                Button("Refresh") { isTrusted = AXIsProcessTrusted() }
            }
            Text("Input monitoring and Accessibility permission may be required when input sharing is available.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}
