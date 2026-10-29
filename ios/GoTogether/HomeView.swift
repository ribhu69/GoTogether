import SwiftUI

// HomeView has been replaced by MapHomeView. This file keeps the shared match-flow
// views still used from MapHomeView's "Find co-riders (classic)" link.

struct MatchesView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let matches = app.matches()
        List {
            if matches.isEmpty {
                ContentUnavailableView("No co-riders yet", systemImage: "person.2.slash",
                    description: Text("Try a wider radius or time window."))
            }
            ForEach(matches) { m in
                NavigationLink { MatchDetailView(match: m) } label: { MatchRow(match: m) }
            }
        }
        .navigationTitle("\(matches.count) co-riders")
    }
}

struct MatchRow: View {
    let match: Match
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.rider.name).font(.headline)
                if match.rider.idVerified { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) }
                Spacer()
                Text("Save ₹\(match.saving)").font(.subheadline.bold()).foregroundStyle(.green)
            }
            Text("→ \(match.rider.destination.name) · \(String(format: "%.1f", match.destGapKm)) km apart · \(match.timeGapMin) min gap")
                .font(.footnote).foregroundStyle(.secondary)
            Text("★ \(String(format: "%.1f", match.rider.rating)) · \(match.rider.trips) trips")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MatchDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let match: Match

    var body: some View {
        List {
            Section("Co-rider") {
                LabeledContent("Name", value: match.rider.name)
                LabeledContent("ID", value: match.rider.idRef)
                LabeledContent("Rating", value: "★ \(String(format: "%.1f", match.rider.rating)) (\(match.rider.trips) trips)")
                LabeledContent("Going to", value: match.rider.destination.name)
            }
            Section("Fare (estimate)") {
                LabeledContent("Solo cab", value: "₹\(match.soloFare)")
                LabeledContent("Your share", value: "₹\(match.sharedFare)")
                LabeledContent("You save", value: "₹\(match.saving)")
            }
            Section {
                Button("Request to share") {
                    app.request(match)
                    dismiss()
                }
                .disabled(app.activeTrip != nil)
            } footer: {
                Text("Both riders' verified IDs are linked to the trip record and shared with the cab driver's platform on request.")
            }
        }
        .navigationTitle(match.rider.name)
    }
}
