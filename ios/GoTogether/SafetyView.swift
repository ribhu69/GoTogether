import SwiftUI

struct SafetyView: View {
    @Environment(AppState.self) private var app
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("You") {
                    LabeledContent("Name", value: app.name)
                    LabeledContent("Phone", value: app.phoneVerified ? "Verified" : "—")
                    LabeledContent("ID", value: "\(app.idType) ••••\(app.idLast4)")
                    LabeledContent("Emergency", value: "\(app.emergencyName) \(app.emergencyPhone)")
                }
                Section("How we keep you traceable") {
                    Label("Every rider is ID + selfie verified", systemImage: "person.badge.shield.checkmark")
                    Label("Each trip is logged with both riders, cab plate and driver", systemImage: "doc.text.magnifyingglass")
                    Label("PIN check before boarding", systemImage: "number.square")
                    Label("One-tap SOS: alerts contact and dials 112", systemImage: "exclamationmark.triangle")
                }

                // Server status
                Section {
                    serverStatusSection
                } header: {
                    Label("Server Status", systemImage: "network")
                }
                Section("SOS history") {
                    if app.safetyLog.isEmpty { Text("None").foregroundStyle(.secondary) }
                    ForEach(app.safetyLog, id: \.self) { Text($0).font(.footnote) }
                }

                Section {
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label("Reset Profile & Re-onboard", systemImage: "arrow.counterclockwise")
                    }
                } footer: {
                    Text("Clears saved profile and returns to onboarding. Use this to change your name, phone, or emergency contact.")
                }
            }
            .adaptiveWidth()
            .navigationTitle("Safety")
            .onAppear { app.fetchServerStatus() }
            .confirmationDialog("Reset profile?", isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button("Reset", role: .destructive) {
                    app.resetProfile()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your profile, ID verification, and emergency contact will be cleared. You'll need to re-onboard.")
            }
        }
    }

    // MARK: - Server status

    private var serverStatusSection: some View {
        Group {
            if !app.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Not connected — register in onboarding", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await app.registerWithServer() }
                        app.fetchServerStatus()
                    } label: {
                        Label("Connect to server", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .disabled(app.name.isEmpty || app.phone.isEmpty)
                }
            } else if let me = app.serverMe {
                statusRow("Connection", value: app.serverReachable ? "Live" : "Unreachable",
                          color: app.serverReachable ? .green : .red)
                statusRow("User ID", value: String(me.userId.prefix(12)))
                if let age = me.locationAgeSec {
                    statusRow("Location", value: age < 30 ? "Fresh (\(Int(age))s ago)" : "Stale (\(Int(age))s ago)",
                              color: age < 30 ? .green : .orange)
                } else {
                    statusRow("Location", value: "Not sent yet", color: .secondary)
                }
                statusRow("Intent", value: me.hasIntent ? (me.intentOpen ? "Open" : "Closed") : "Not set",
                          color: me.intentOpen ? .green : .secondary)
                if let dest = me.intentDest {
                    statusRow("Destination", value: dest)
                }
                if let comfort = me.comfortRadiusKm {
                    statusRow("Comfort", value: "\(Int(comfort)) km")
                }
                statusRow("Server time", value: Date(timeIntervalSince1970: me.serverTs).formatted(date: .omitted, time: .shortened))

                if !app.serverReachable {
                    Button {
                        app.reconnectToServer()
                    } label: {
                        Label("Retry connection", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Fetching server status…").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func statusRow(_ label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).foregroundStyle(color)
        }
    }
}
