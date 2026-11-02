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
}
