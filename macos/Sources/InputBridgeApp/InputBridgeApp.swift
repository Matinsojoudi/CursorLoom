import SwiftUI
import ApplicationServices
import AppKit

@main
struct InputBridgeApp: App {
    var body: some Scene {
        WindowGroup { ContentView().frame(minWidth: 600, minHeight: 510) }
    }
}

struct ContentView: View {
    @StateObject private var controller = SharingController()
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var host = ""
    @State private var port = "24800"
    @State private var certificateURL: URL?
    @State private var password = ""
    @State private var fingerprint = ""
    @State private var errorMessage = ""
    @State private var showConsent = false
    @State private var shareClipboard = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CursorLoom — experimental sender").font(.title2.bold())
            Text("One-way test only. Local input remains active while sharing. Clipboard is opt-in on both devices.")
                .foregroundStyle(.secondary)
            Form {
                TextField("Windows IP or hostname", text: $host)
                TextField("TCP port", text: $port)
                HStack {
                    Text(certificateURL?.lastPathComponent ?? "No identity selected")
                    Button("Choose PKCS#12…") { chooseCertificate() }
                }
                SecureField("Identity password", text: $password)
                TextField("Windows certificate SHA-256 fingerprint", text: $fingerprint)
            }
            Toggle("Also send clipboard text (may contain sensitive data)", isOn: $shareClipboard).disabled(controller.sharing)
            HStack {
                Button("Connect") { connect() }.disabled(controller.connected)
                Button("Disconnect") { controller.stop() }
                Button("Share input…") { showConsent = true }.disabled(!controller.connected || controller.sharing)
                Button("Stop sharing") { controller.stopSharing() }.disabled(!controller.sharing)
            }
            Text(controller.status).font(.headline)
            if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
            Divider()
            Label(isTrusted ? "Accessibility permission granted" : "Accessibility permission needed", systemImage: isTrusted ? "checkmark.shield" : "exclamationmark.shield")
            HStack {
                Button("Request Accessibility") {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                    isTrusted = AXIsProcessTrusted()
                }
                Button("Request Input Monitoring") { _ = CGRequestListenEventAccess() }
                Button("Refresh permissions") { isTrusted = AXIsProcessTrusted() }
            }
        }
        .padding(20)
        .confirmationDialog("Share all keyboard and mouse activity with the connected Windows computer?", isPresented: $showConsent) {
            Button("Start sharing") {
                do { try controller.startSharing(shareClipboard: shareClipboard); errorMessage = "" }
                catch { errorMessage = "Cannot start capture: \(error.localizedDescription)" }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Local input will also remain active. Do not type passwords while sharing. You can stop using the Stop sharing button.")
        }
        .onDisappear { controller.stop() }
    }

    private func chooseCertificate() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { certificateURL = panel.url }
    }

    private func connect() {
        guard let certificateURL, let number = UInt16(port), number > 0, !host.isEmpty else {
            errorMessage = "Provide a host, valid port and PKCS#12 identity."
            return
        }
        do {
            let data = try Data(contentsOf: certificateURL, options: [.mappedIfSafe])
            try controller.connect(host: host, port: number, certificate: data, password: password, peerFingerprint: fingerprint)
            password = ""
            errorMessage = ""
        } catch {
            password = ""
            errorMessage = "Connection setup failed: \(error.localizedDescription)"
        }
    }
}
