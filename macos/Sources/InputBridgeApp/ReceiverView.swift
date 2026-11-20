import SwiftUI
import AppKit
import ApplicationServices

struct ReceiverView: View {
    @StateObject private var controller = ReceiverController()
    @State private var certificateURL: URL?
    @State private var password = ""
    @State private var fingerprint = ""
    @State private var port = "24800"
    @State private var consent = false
    @State private var allowClipboard = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CursorLoom — experimental receiver").font(.title2.bold())
            Text("Allow only a verified device on a trusted test network. This receiver has not been tested with Windows.")
                .foregroundStyle(.secondary)
            Form {
                TextField("TCP port", text: $port)
                HStack {
                    Text(certificateURL?.lastPathComponent ?? "No identity selected")
                    Button("Choose PKCS#12…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK { certificateURL = panel.url }
                    }
                }
                SecureField("Identity password", text: $password)
                TextField("Controller certificate SHA-256 fingerprint", text: $fingerprint)
            }.disabled(controller.active)
            Toggle("Allow this verified device to control this Mac", isOn: $consent).disabled(controller.active)
            Toggle("Allow incoming clipboard text to replace local clipboard", isOn: $allowClipboard).disabled(controller.active)
            HStack {
                Button("Start receiver") { start() }.disabled(controller.active || !consent)
                Button("Stop") { controller.stop() }.disabled(!controller.active)
            }
            Text(controller.status).font(.headline)
            if !error.isEmpty { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Text(AXIsProcessTrusted() ? "Accessibility permission granted" : "Accessibility permission required for input injection")
            Spacer()
        }
        .padding(20)
        .onChange(of: controller.active) { active in
            if !active { consent = false; allowClipboard = false }
        }
        .onDisappear { controller.stop(); password = ""; consent = false; allowClipboard = false }
    }

    private func start() {
        guard let certificateURL, let parsedPort = UInt16(port), parsedPort > 0 else {
            error = "Choose an identity and valid port."
            return
        }
        do {
            try controller.start(port: parsedPort, certificate: Data(contentsOf: certificateURL), password: password,
                                 peerFingerprint: fingerprint, consent: consent, allowClipboard: allowClipboard)
            password = ""
            error = ""
        } catch {
            password = ""
            self.error = "Cannot start receiver: \(error.localizedDescription)"
        }
    }
}
