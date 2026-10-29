import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var otp = ""
    @State private var otpSent = false
    @State private var serverURL = ""
    @State private var useServer = false

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section("Server (optional)") {
                    TextField("http://localhost:8080", text: $serverURL)
                        .keyboardType(.URL).autocapitalization(.none)
                        .onAppear { serverURL = app.api.baseURL }
                    Toggle("Use server for live matching", isOn: $useServer)
                    if app.isConnected {
                        Label("Connected as \(app.api.userId?.prefix(8) ?? "")…", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
                Section("1 · Phone") {
                    TextField("Full name", text: $app.name)
                    Picker("Gender", selection: $app.gender) {
                        ForEach(Gender.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Phone number", text: $app.phone).keyboardType(.phonePad)
                    if app.phoneVerified {
                        Label("Phone verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else if otpSent {
                        TextField("OTP (demo: 123456)", text: $otp).keyboardType(.numberPad)
                        Button("Verify OTP") {
                            if useServer {
                                Task { await app.verifyPhoneOnServer(otp) }
                            } else {
                                app.phoneVerified = (otp == "123456")
                            }
                        }
                    } else {
                        Button("Send OTP") { otpSent = true }.disabled(app.phone.count < 8)
                    }
                }
                Section {
                    Picker("ID type", selection: $app.idType) {
                        ForEach(["Aadhaar", "Passport", "Driving licence"], id: \.self) { Text($0) }
                    }
                    TextField("Last 4 digits", text: $app.idLast4).keyboardType(.numberPad)
                    if app.idVerified {
                        Label("ID + selfie verified", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Button("Simulate ID + selfie check") {
                            if useServer {
                                Task { await app.verifyIdOnServer(app.idLast4) }
                            } else {
                                app.idVerified = app.idLast4.count == 4
                            }
                        }.disabled(!app.phoneVerified)
                    }
                } header: { Text("2 · Government ID") } footer: {
                    Text("Demo only. Production: DigiLocker / e-KYC plus liveness selfie. The full ID never leaves our servers; co-riders see a masked reference.")
                }
                Section {
                    TextField("Contact name", text: $app.emergencyName)
                    TextField("Contact phone", text: $app.emergencyPhone).keyboardType(.phonePad)
                } header: { Text("3 · Emergency contact") } footer: {
                    Text("Notified with live trip details if you press SOS.")
                }

                // Register with server
                if useServer && app.phoneVerified && app.idVerified && !app.name.isEmpty && !app.emergencyPhone.isEmpty && !app.isConnected {
                    Section {
                        Button("Register on server") {
                            app.api.baseURL = serverURL
                            Task { await app.registerWithServer() }
                        }
                    }
                }
            }
            .navigationTitle("Welcome to GoTogether")
        }
    }
}
