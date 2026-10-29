import SwiftUI

struct TripView: View {
    @Environment(AppState.self) private var app
    @State private var confirmSOS = false

    var body: some View {
        NavigationStack {
            Group {
                if let t = app.activeTrip { active(t) } else { idle }
            }
            .navigationTitle("Trip")
        }
    }

    private var idle: some View {
        List {
            if app.history.isEmpty {
                ContentUnavailableView("No active trip", systemImage: "car", description: Text("Find a co-rider to start."))
            }
            ForEach(app.history) { t in
                Section("\(t.id) · \(t.match.rider.name)") {
                    ForEach(t.events, id: \.self) { Text($0).font(.footnote) }
                }
            }
        }
    }

    private func active(_ t: Trip) -> some View {
        List {
            Section {
                LabeledContent("Status", value: t.status.rawValue)
                LabeledContent("Trip ID", value: t.id)
                LabeledContent("Co-rider", value: t.match.rider.name)
                LabeledContent("Your fare", value: "₹\(t.match.sharedFare)")
            }
            if t.status != .requested {
                Section("Boarding") {
                    LabeledContent("Cab", value: t.cabPlate)
                    LabeledContent("Driver", value: t.driverName)
                    LabeledContent("Trip PIN", value: t.pin)
                }
                Section("Safety") {
                    ShareLink(item: app.shareText(t)) { Label("Share trip with a friend", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { confirmSOS = true } label: {
                        Label("SOS", systemImage: "exclamationmark.triangle.fill")
                    }
                }
                Section {
                    Button("Complete trip") { app.complete() }
                    Button("Cancel", role: .cancel) { app.cancel() }
                }
            }
            Section("Log") { ForEach(t.events, id: \.self) { Text($0).font(.footnote) } }
        }
        .confirmationDialog("Raise SOS?", isPresented: $confirmSOS, titleVisibility: .visible) {
            Button("Alert contact & call 112", role: .destructive) {
                app.raiseSOS()
                if let url = URL(string: "tel://112") { UIApplication.shared.open(url) }
            }
        } message: {
            Text("Your emergency contact gets live trip details, co-rider ID and cab plate.")
        }
    }
}
