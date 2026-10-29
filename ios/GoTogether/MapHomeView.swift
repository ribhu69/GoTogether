import SwiftUI
import MapKit

struct MapHomeView: View {
    @Environment(AppState.self) private var app
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: Mock.airport.coord, latitudinalMeters: 30_000, longitudinalMeters: 30_000))
    @State private var userTracking: MKUserTrackingMode = .follow
    @State private var showSheet = false
    @State private var sheetTab = 0   // 0=search, 1=intents
    @State private var tappedIntent: TravelIntent?

    private let originSpanKm: Double = 0.5

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .bottom) {
            Map(position: $position, interactionModes: .all) {
                // My origin (airport)
                Annotation("You · Origin", coordinate: app.myOrigin.coord) {
                    Circle().fill(.blue).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }

                // My destination
                Annotation("Your destination", coordinate: app.myDest.coord) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title).foregroundStyle(.red)
                }

                // Comfort radius around my destination
                MapCircle(center: app.myDest.coord, radius: app.myComfortKm * 1000)
                    .foregroundStyle(.orange.opacity(0.15))
                    .mapOverlayLevel(level: .aboveLabels)

                // Origin "same area" circle
                MapCircle(center: app.myOrigin.coord, radius: originSpanKm * 1000)
                    .foregroundStyle(.blue.opacity(0.08))
                    .mapOverlayLevel(level: .aboveLabels)

                // Open travelers pinned at their origin
                ForEach(openVisible) { intent in
                    Annotation(intent.rider.name, coordinate: intent.origin.coord) {
                        VStack(spacing: 2) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2).foregroundStyle(.green)
                            Text(intent.rider.name.components(separatedBy: " ").first ?? "")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .onTapGesture { tappedIntent = intent }
                    }

                    // Line from their origin to their destination
                    MapPolyline(coordinates: [intent.origin.coord, intent.rider.destination.coord])
                        .stroke(.green.opacity(0.35), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
            .safeAreaInset(edge: .bottom) { bottomBar }
        }
        .onAppear { app.refreshIntents() }
        .onChange(of: app.search.verifiedOnly) { _, _ in app.refreshIntents() }
        .onChange(of: app.search.sameGenderOnly) { _, _ in app.refreshIntents() }
        .onChange(of: app.myComfortKm) { _, _ in app.syncIntent() }
        .onChange(of: app.iAmOpen) { _, _ in app.syncIntent() }
        .onChange(of: app.myDest) { _, _ in app.syncIntent() }
        .task {
            while !Task.isCancelled {
                app.pollPending()
                app.refreshIntents()
                try? await Task.sleep(for: .seconds(4))
            }
        }
        .sheet(isPresented: $showSheet) { sheetContent }
        .sheet(item: $tappedIntent) { intent in intentDetail(intent) }
    }

    // Only show intents whose origin is within the origin-span circle.
    private var openVisible: [TravelIntent] {
        app.openIntents.filter { Geo.km(app.myOrigin, $0.origin) <= originSpanKm }
    }

    // ---------- Bottom bar ----------

    private var bottomBar: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("To: \(app.myDest.name)").font(.subheadline.weight(.semibold))
                        if app.isConnected { Circle().fill(.green).frame(width: 6, height: 6) }
                    }
                    Text("Comfort: \(Int(app.myComfortKm)) km · \(openVisible.count) nearby").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: $app.iAmOpen) {
                    Text("Open").font(.caption).bold()
                }
                .toggleStyle(.button).tint(app.iAmOpen ? .green : .gray)
                Button { showSheet = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.title3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }

    // ---------- Sheet ----------

    private var sheetContent: some View {
        @Bindable var app = app
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $sheetTab) {
                    Text("Search").tag(0)
                    Text("Nearby Open").tag(1)
                }
                .pickerStyle(.segmented).padding()
                Group {
                    if sheetTab == 0 { searchTab } else { intentsTab }
                }
            }
            .navigationTitle("Find a co-rider")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
        }
    }

    private var searchTab: some View {
        @Bindable var app = app
        return Form {
            Section("Destination") {
                Picker("Destination", selection: $app.myDest) {
                    ForEach(Mock.places.filter { $0.id != "BLR" }) { Text($0.name).tag($0) }
                }
            }
            Section("Comfort range (how far from your destination are you OK?)") {
                VStack(alignment: .leading) {
                    Text("\(Int(app.myComfortKm)) km").font(.title2.bold()).foregroundStyle(.orange)
                    Slider(value: $app.myComfortKm, in: 1...10, step: 1)
                }
                Text("You'll be shown to people whose destination is within this radius of yours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filters") {
                Toggle("Verified riders only", isOn: $app.search.verifiedOnly)
                Toggle("Same gender only", isOn: $app.search.sameGenderOnly)
            }
            Section {
                NavigationLink("Find co-riders (classic)") { MatchesView() }
            }
        }
    }

    private var intentsTab: some View {
        @Bindable var app = app
        let hits = app.matchingOpenIntents()
        return Group {
            if hits.isEmpty && app.serverPending.isEmpty {
                ContentUnavailableView("No open travelers match", systemImage: "person.2.slash",
                    description: Text("Try a wider comfort radius or fewer filters."))
            } else {
                List {
                    // Server pending matches (incoming requests from others)
                    if !app.serverPending.isEmpty {
                        Section("📲 Incoming match requests") {
                            ForEach(app.serverPending, id: \.matchId) { sm in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sm.fromUserName).font(.headline)
                                        Text("Wants to share · ~\(String(format: "%.1f", sm.destGapKm ?? 0)) km").font(.caption)
                                    }
                                    Spacer()
                                    HStack(spacing: 8) {
                                        Button("Accept") {
                                            Task { await app.acceptServerMatch(sm) }
                                            showSheet = false
                                        }.buttonStyle(.borderedProminent).controlSize(.small)
                                    }
                                }
                            }
                        }
                    }
                    if !hits.isEmpty {
                        Section("\(hits.count) people would be notified") {
                            Text("These users marked themselves Open near your origin and their destination falls within your \(Int(app.myComfortKm)) km radius.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(hits) { i in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(i.rider.name).font(.headline)
                                    if i.rider.idVerified {
                                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                    }
                                }
                                Text("→ \(i.rider.destination.name) · \(String(format: "%.1f", Geo.km(app.myDest, i.rider.destination))) km from your dest")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Comfort: \(Int(i.comfortRadiusKm)) km · ★ \(String(format: "%.1f", i.rider.rating))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Share") { app.requestIntent(i); showSheet = false }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .disabled(app.activeTrip != nil)
                        }
                    }
                }
            }
        }
    }

    private func intentDetail(_ i: TravelIntent) -> some View {
        NavigationStack {
            List {
                Section("Traveler") {
                    LabeledContent("Name", value: i.rider.name)
                    LabeledContent("ID", value: i.rider.idRef)
                    LabeledContent("Rating", value: "★ \(String(format: "%.1f", i.rider.rating)) (\(i.rider.trips) trips)")
                    LabeledContent("Going to", value: i.rider.destination.name)
                    LabeledContent("Comfort range", value: "\(Int(i.comfortRadiusKm)) km")
                }
                Section("Distance check") {
                    LabeledContent("From", value: "\(String(format: "%.1f", Geo.km(app.myDest, i.rider.destination))) km between destinations")
                    LabeledContent("Est. your fare", value: "₹\(Int(Fare.shared(you: app.myDest, them: i.rider.destination).rounded()))")
                }
                Section {
                    Button("Share ride") { app.requestIntent(i) }
                        .disabled(app.activeTrip != nil)
                }
            }
            .navigationTitle(i.rider.name)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
        }
    }
}
