import SwiftUI
import AppKit
import ApplicationServices

@main
struct CursorLoomApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("CursorLoom", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 420, minHeight: 460)
                .onDisappear { model.disconnect() }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CursorLoom").font(.largeTitle.bold())
            Text(model.status).foregroundStyle(.secondary)

            Toggle("Let another device control this Mac", isOn: $model.allowControl)
                .toggleStyle(.switch)

            Divider()

            Text("Devices on this network").font(.headline)
            if model.devices.isEmpty {
                Text("Searching…").foregroundStyle(.secondary)
            }
            ForEach(model.devices) { device in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name).font(.body.weight(.medium))
                        Text(model.sideLabel(for: device)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.connectedDevice == device.id {
                        Button("Disconnect") { model.disconnect() }
                    } else {
                        Button("Connect") { model.connect(device) }
                            .disabled(model.connectedDevice != nil)
                    }
                    Menu("Position") {
                        ForEach(AppModel.Side.allCases) { side in
                            Button("Place \(side.label)") { model.place(device, side: side) }
                        }
                        Button("Not placed") { model.place(device, side: nil) }
                    }
                    .fixedSize()
                }
                .padding(.vertical, 2)
            }

            Divider()

            if model.connectedDevice != nil {
                HStack {
                    Button(model.sharing ? "Stop sharing" : "Share mouse & keyboard") {
                        model.sharing ? model.stopSharing() : model.share()
                    }
                    .buttonStyle(.borderedProminent)
                    if !model.sharing {
                        Text("Everything you type is also sent to the other Mac until you stop.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !model.errorText.isEmpty {
                Text(model.errorText).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }

            Spacer(minLength: 0)
            HStack {
                Text(AXIsProcessTrusted() ? "Accessibility: allowed" : "Accessibility: needed to type on this Mac")
                    .font(.caption)
                Spacer()
                Button("Permissions…") { openPrivacySettings() }
                    .controlSize(.small)
            }
        }
        .padding(20)
        .alert("Allow this device to control this Mac?",
               isPresented: Binding(get: { model.pendingRequest != nil },
                                    set: { if !$0 { model.answerRequest(false) } })) {
            Button("Allow") { model.answerRequest(true) }
            Button("Deny", role: .cancel) { model.answerRequest(false) }
        } message: {
            Text("Only accept if you just started a connection from your own device.")
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
