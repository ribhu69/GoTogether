import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @State private var otp = ""
    @State private var otpSent = false
    @State private var serverURL = ""
    @State private var useServer = false
    @State private var step = 0   // 0=phone, 1=id, 2=emergency, 3=server+done
    @State private var quickStartAvailable = false

    var body: some View {
        @Bindable var app = app

        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.blue.opacity(0.15), Color.indigo.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "car.2.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                        .padding(.top, 24)

                    Text("GoTogether")
                        .font(.largeTitle.weight(.bold))

                    Text("Share cabs. Split fares. Stay safe.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 24)

                // Step indicator
                HStack(spacing: 0) {
                    ForEach(0..<4) { i in
                        Capsule()
                            .fill(i <= step ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 4)
                        if i < 3 { Spacer().frame(width: 6) }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 20)

                // Quick start
                if quickStartAvailable {
                    Button {
                        app.quickStart()
                        step = 3  // jump to server step
                    } label: {
                        Label("Quick start — use saved profile", systemImage: "person.fill.checkmark")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }

                // Form content
                TabView(selection: $step) {
                    phoneStep.tag(0)
                    idStep.tag(1)
                    emergencyStep.tag(2)
                    serverStep.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: 340)

                // Next / Done button
                Button(action: nextStep) {
                    HStack {
                        Text(step < 3 ? "Continue" : "Get Started")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .adaptiveWidth()
        }
        .onAppear {
            app.loadSavedProfile()
            quickStartAvailable = app.hasSavedProfile
            serverURL = app.api.baseURL
        }
    }

    // MARK: - Steps

    private var phoneStep: some View {
        @Bindable var app = app
        return Form {
            Section {
                TextField("Full name", text: $app.name)
                    .textContentType(.name)
                Picker("Gender", selection: $app.gender) {
                    ForEach(Gender.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Phone number", text: $app.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)

                if app.phoneVerified {
                    Label("Phone verified ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else if otpSent {
                    HStack {
                        TextField("OTP", text: $otp).keyboardType(.numberPad)
                        Button("Verify") { verifyPhone() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Text("Demo OTP: 123456").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Send OTP") { otpSent = true }.disabled(app.phone.count < 8)
                }
            } header: {
                Label("Your Identity", systemImage: "person.circle")
            } footer: {
                Text("We never share your full phone number with co-riders.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var idStep: some View {
        @Bindable var app = app
        return Form {
            Section {
                Picker("ID type", selection: $app.idType) {
                    ForEach(["Aadhaar", "Passport", "Driving licence"], id: \.self) { Text($0) }
                }
                TextField("Last 4 digits", text: $app.idLast4).keyboardType(.numberPad)

                if app.idVerified {
                    Label("ID + selfie verified ✓", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Simulate ID + selfie check") {
                        if useServer {
                            Task { await app.verifyIdOnServer(app.idLast4) }
                        } else {
                            app.idVerified = app.idLast4.count == 4
                        }
                    }
                    .disabled(!app.phoneVerified)
                }
            } header: {
                Label("Government ID", systemImage: "creditcard.and.123")
            } footer: {
                Text("Full ID never leaves our servers. Co-riders see only a masked reference.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emergencyStep: some View {
        @Bindable var app = app
        return Form {
            Section {
                TextField("Contact name", text: $app.emergencyName)
                    .textContentType(.name)
                TextField("Contact phone", text: $app.emergencyPhone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            } header: {
                Label("Emergency Contact", systemImage: "exclamationmark.shield")
            } footer: {
                Text("They get live trip details if you press SOS — cab plate, co-rider ID, and location.")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var serverStep: some View {
        @Bindable var app = app
        return Form {
            Section {
                Toggle("Use server for live matching", isOn: $useServer)
            } footer: {
                if !useServer {
                    Text("Without the server you can still plan trips, but you won't see other travelers in real time.")
                }
            }

            if useServer {
                Section {
                    TextField("Server URL", text: $serverURL)
                        .keyboardType(.URL).autocapitalization(.none)
                } header: {
                    Label("Server URL", systemImage: "network")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Which URL to use:").font(.caption.weight(.medium))
                        Text("• iOS Simulator → http://localhost:8080")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("• Real device (same WiFi as Mac) → http://<Mac-IP>:8080")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Run ./start.sh in the server folder to see the Mac's IP. If you're on VPN, use the en0/WiFi IP, not the VPN IP.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Section {
                    if app.isConnected {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected to server").font(.subheadline.weight(.medium))
                                Text("ID: \(app.api.userId?.prefix(10) ?? "")…")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            app.api.baseURL = serverURL
                            Task { await app.registerWithServer() }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Register on server")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.name.isEmpty || !app.phoneVerified || !app.idVerified || app.emergencyPhone.isEmpty)
                    }
                } footer: {
                    if !app.isConnected {
                        Text("The server must be running on your Mac before you tap Register. Run: cd server && ./start.sh")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private var canAdvance: Bool {
        switch step {
        case 0: return app.phoneVerified && !app.name.isEmpty
        case 1: return app.idVerified
        case 2: return !app.emergencyName.isEmpty && !app.emergencyPhone.isEmpty
        case 3: return !useServer || app.isConnected
        default: return false
        }
    }

    private func nextStep() {
        if step < 3 {
            withAnimation { step += 1 }
        } else {
            app.saveProfile()
        }
    }

    private func verifyPhone() {
        if useServer {
            Task { await app.verifyPhoneOnServer(otp) }
        } else {
            app.phoneVerified = (otp == "123456")
        }
    }
}