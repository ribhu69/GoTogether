import SwiftUI
import MapKit

struct MapHomeView: View {
    @Environment(AppState.self) private var app
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: Place.defaultOrigin.coord, latitudinalMeters: 30_000, longitudinalMeters: 30_000))
    @State private var showSheet = false
    @State private var sheetTab = 0   // 0=destination, 1=search, 2=intents
    @State private var tappedIntent: TravelIntent?
    @State private var selectedPeer: PeerLocation?
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showRideApps = false
    @State private var hasInitialCenter = false

    private let originSpanKm: Double = 0.5

    var body: some View {
        @Bindable var app = app

        ZStack(alignment: .top) {
            Map(position: $position, interactionModes: .all) {
                // User location
                UserAnnotation()

                // My origin
                Annotation("You", coordinate: app.myOrigin.coord) {
                    Circle().fill(.blue).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }

                // My destination
                if app.myDest.id != app.myOrigin.id {
                    Annotation("Your destination", coordinate: app.myDest.coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title).foregroundStyle(.red)
                    }

                    // Route line
                    MapPolyline(coordinates: [app.myOrigin.coord, app.myDest.coord])
                        .stroke(.blue.opacity(0.5), lineWidth: 2)
                }

                // Comfort radius
                MapCircle(center: app.myDest.coord, radius: app.myComfortKm * 1000)
                    .foregroundStyle(.orange.opacity(0.15))
                    .mapOverlayLevel(level: .aboveLabels)

                // Origin span circle
                MapCircle(center: app.myOrigin.coord, radius: originSpanKm * 1000)
                    .foregroundStyle(.blue.opacity(0.08))
                    .mapOverlayLevel(level: .aboveLabels)

                // Peer live locations
                ForEach(app.peerLocations) { peer in
                    Annotation(peer.name, coordinate: peer.coord) {
                        VStack(spacing: 2) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2).foregroundStyle(.green)
                            Text(peer.name.components(separatedBy: " ").first ?? peer.name)
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .onTapGesture { selectedPeer = peer }
                    }

                    // Line to their destination
                    if let dest = peer.destination?.coord {
                        MapPolyline(coordinates: [peer.coord, dest])
                            .stroke(.green.opacity(0.35), lineWidth: 1.5)
                    }
                }

                // Open traveler intents
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

                    MapPolyline(coordinates: [intent.origin.coord, intent.rider.destination.coord])
                        .stroke(.green.opacity(0.35), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
            .safeAreaInset(edge: .bottom) { bottomBar }

            // Search bar
            VStack(spacing: 0) {
                searchBar
                if isSearching {
                    if searchText.isEmpty {
                        quickDestinations
                    } else if !searchResults.isEmpty {
                        searchResultsList
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .onAppear {
            app.location.request()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                app.updateOriginFromLocation()
                recenterOnUser()
                hasInitialCenter = true
            }
            app.refreshIntents()
        }
        .onChange(of: app.location.location) { _, _ in
            app.updateOriginFromLocation()
            if !hasInitialCenter {
                recenterOnUser()
                hasInitialCenter = true
            }
        }
        .onChange(of: app.search.verifiedOnly) { _, _ in app.refreshIntents() }
        .onChange(of: app.search.sameGenderOnly) { _, _ in app.refreshIntents() }
        .onChange(of: searchText) { _, newValue in performSearch(newValue) }
        .onChange(of: app.myComfortKm) { _, _ in app.syncIntent() }
        .onChange(of: app.iAmOpen) { _, _ in app.syncIntent() }
        .onChange(of: app.myDest) { _, _ in app.syncIntent() }
        .task {
            // Polling loop: refresh intents + peer locations every 3 seconds
            while !Task.isCancelled {
                app.pollPending()
                app.refreshIntents()
                app.syncLocation()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .sheet(isPresented: $showSheet) { sheetContent }
        .sheet(item: $tappedIntent) { intent in intentDetail(intent) }
        .sheet(item: $selectedPeer) { peer in PeerChatSheet(peer: peer) }
        .sheet(isPresented: $showRideApps) { rideAppsSheet }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search destination…", text: $searchText)
                .textFieldStyle(.plain)
                .onTapGesture { isSearching = true }
            if isSearching {
                Button { closeSearch() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(searchResults, id: \.self) { item in
                    Button {
                        selectSearchResult(item)
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Unknown")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                if let addr = item.placemark.title {
                                    Text(addr).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 12)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxHeight: 240)
        .shadow(radius: 2)
    }

    private func performSearch(_ query: String) {
        guard query.count >= 2 else { searchResults = []; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(
            center: app.myOrigin.coord,
            latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        MKLocalSearch(request: req).start { response, _ in
            searchResults = response?.mapItems ?? []
        }
    }

    private func selectSearchResult(_ item: MKMapItem) {
        let c = item.placemark.coordinate
        let name = item.name ?? "Selected"
        app.myDest = Place(id: "search-\(name.hashValue)", name: name,
                           lat: c.latitude, lon: c.longitude)
        app.hasDestination = true
        closeSearch()
    }

    private func closeSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Map helpers

    private func recenterOnUser() {
        let span = app.myComfortKm * 2 * 1000 + 2000
        withAnimation(.easeInOut(duration: 0.3)) {
            position = .region(MKCoordinateRegion(
                center: app.myOrigin.coord,
                latitudinalMeters: span, longitudinalMeters: span))
        }
    }

    private var openVisible: [TravelIntent] {
        app.openIntents.filter { Geo.km(app.myOrigin, $0.origin) <= originSpanKm }
    }

    private var quickDestinations: some View {
        @Bindable var app = app
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(Mock.places.filter { $0.id != "BLR" }) { place in
                    Button {
                        app.myDest = place
                        app.hasDestination = true
                        closeSearch()
                    } label: {
                        HStack {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(.indigo)
                            Text(place.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            if app.myDest.id == place.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                            Text(String(format: "%.1f km", Geo.km(app.myOrigin, place)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 12)
                }
                if let home = app.homeAddress {
                    Divider()
                    Button {
                        app.myDest = home; app.hasDestination = true; closeSearch()
                    } label: {
                        HStack {
                            Image(systemName: "house.fill").foregroundStyle(.orange)
                            Text("Home — \(home.name)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(String(format: "%.1f km", Geo.km(app.myOrigin, home)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxHeight: 320)
        .shadow(radius: 2)
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        @Bindable var app = app
        return VStack(spacing: 0) {
            Divider()

            // Ride-hailing quick actions
            if app.myDest.id != app.myOrigin.id && app.myDest.id != "BLR" {
                rideHailStrip
            }

            HStack(spacing: 12) {
                Button {
                    isSearching = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("To: \(app.myDest.name)").font(.subheadline.weight(.semibold)).lineLimit(1)
                            if app.isConnected { Circle().fill(.green).frame(width: 6, height: 6) }
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Text("Comfort: \(Int(app.myComfortKm)) km · \(openVisible.count) nearby")
                                .font(.caption).foregroundStyle(.secondary)
                            if app.isRefreshing {
                                ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                            } else if let ts = app.lastRefreshAt {
                                Circle().fill(.clear).frame(width: 4, height: 4)
                                    .overlay(Text(ts, style: .timer).font(.system(size: 9)).foregroundStyle(.tertiary))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()

                // Recenter
                Button { recenterOnUser() } label: {
                    Image(systemName: "location.fill").font(.title3)
                }
                .tint(.blue)

                // Home button
                if let home = app.homeAddress {
                    Button {
                        app.myDest = home
                    } label: {
                        Image(systemName: app.myDest.id == "home" ? "house.fill" : "house")
                            .font(.title3)
                    }
                    .tint(.orange)
                }

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

    // MARK: - Ride-hailing strip

    private var rideHailStrip: some View {
        HStack(spacing: 8) {
            Text("Book a cab:").font(.caption.weight(.medium)).foregroundStyle(.secondary)

            ForEach(RideHailing.apps, id: \.name) { ra in
                Button {
                    RideHailing.open(ra, from: app.myOrigin, to: app.myDest)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                        Text(ra.name)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color(hex: ra.color) ?? .blue, in: Capsule())
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Button { showRideApps = true } label: {
                Image(systemName: "ellipsis").font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private var rideAppsSheet: some View {
        NavigationStack {
            List {
                Section("Book a ride to \(app.myDest.name)") {
                    ForEach(RideHailing.apps, id: \.name) { ra in
                        Button {
                            RideHailing.open(ra, from: app.myOrigin, to: app.myDest)
                        } label: {
                            HStack {
                                Label(ra.name, systemImage: "car.fill")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.forward.app")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Button {
                        RideHailing.openUberUniversal(from: app.myOrigin, to: app.myDest)
                    } label: {
                        Label("Uber (web fallback)", systemImage: "globe")
                    }
                } footer: {
                    Text("Opens the ride-hailing app with pickup and drop-off pre-filled. Falls back to App Store if not installed.")
                }
            }
            .navigationTitle("Book a Cab")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium])
        }
    }

    // MARK: - Sheet (destination picker + search + intents)

    private var sheetContent: some View {
        @Bindable var app = app
        return NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $sheetTab) {
                    Text("Destination").tag(0)
                    Text("Search").tag(1)
                    Text("Nearby").tag(2)
                }
                .pickerStyle(.segmented).padding()

                TabView(selection: $sheetTab) {
                    destTab.tag(0)
                    searchTab.tag(1)
                    intentsTab.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("Find a co-rider")
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
        }
    }

    private var destTab: some View {
        @Bindable var app = app
        return Form {
            Section("Quick destinations") {
                ForEach(Mock.places.filter { $0.id != "BLR" }) { place in
                    HStack {
                        Label(place.name, systemImage: "mappin")
                        Spacer()
                        if app.myDest.id == place.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { app.myDest = place; app.hasDestination = true; showSheet = false }
                }
            }
            if let home = app.homeAddress {
                Section {
                    Button {
                        app.myDest = home; app.hasDestination = true; showSheet = false
                    } label: {
                        Label("🏠 \(home.name)", systemImage: "house.fill")
                    }
                }
            }
            Section {
                Button {
                    app.homeAddress = app.myDest
                } label: {
                    Label("Save current destination as home", systemImage: "bookmark.fill")
                }
                .disabled(app.myDest.id == app.myOrigin.id || app.myDest.id == "home")
            }
        }
    }

    private var searchTab: some View {
        @Bindable var app = app
        let hits = app.matchingOpenIntents()
        return Form {
            Section("Comfort range") {
                VStack(alignment: .leading) {
                    Text("\(Int(app.myComfortKm)) km").font(.title2.bold()).foregroundStyle(.orange)
                    Slider(value: $app.myComfortKm, in: 1...10, step: 1)
                }
                Text("Co-riders whose destination falls within this radius of yours will be shown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Filters") {
                Toggle("Verified riders only", isOn: $app.search.verifiedOnly)
                Toggle("Same gender only", isOn: $app.search.sameGenderOnly)
            }

            // ── Results ──
            if app.isConnected {
                if !app.serverPending.isEmpty {
                    Section("📲 Incoming match requests") {
                        ForEach(app.serverPending, id: \.matchId) { sm in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sm.fromUserName).font(.headline)
                                    Text("Wants to share · ~\(String(format: "%.1f", sm.destGapKm ?? 0)) km").font(.caption)
                                }
                                Spacer()
                                Button("Accept") {
                                    Task { await app.acceptServerMatch(sm) }
                                    showSheet = false
                                }.buttonStyle(.borderedProminent).controlSize(.small)
                            }
                        }
                    }
                }

                if !hits.isEmpty {
                    Section("\(hits.count) matching near \(app.myDest.name)") {
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
                                }
                                Spacer()
                                Button("Share") {
                                    app.requestIntent(i)
                                    showSheet = false
                                }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .disabled(app.activeTrip != nil)
                            }
                        }
                    }
                } else if app.serverPending.isEmpty {
                    Section {
                        if app.isRefreshing {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Looking for co-riders near \(app.myDest.name)…")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("No matches yet", systemImage: "person.2.slash")
                                    .foregroundStyle(.secondary)
                                Text("Toggle 'Open' so others can find you. When someone nearby goes Open, they'll appear here.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Server not connected", systemImage: "wifi.slash")
                            .foregroundStyle(.secondary)
                        Text("Go to the onboarding screen to register with the GoTogether server for live matching.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var intentsTab: some View {
        @Bindable var app = app
        let hits = app.matchingOpenIntents()
        return Group {
            if hits.isEmpty && app.serverPending.isEmpty {
                if app.isRefreshing {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Scanning for open travelers…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No open travelers nearby",
                        systemImage: "person.2.slash",
                        description: Text("Toggle 'Open' so others can find you, or wait for someone nearby to go Open.")
                    )
                }
            } else {
                List {
                    if !app.serverPending.isEmpty {
                        Section("📲 Incoming match requests") {
                            ForEach(app.serverPending, id: \.matchId) { sm in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sm.fromUserName).font(.headline)
                                        Text("Wants to share · ~\(String(format: "%.1f", sm.destGapKm ?? 0)) km").font(.caption)
                                    }
                                    Spacer()
                                    Button("Accept") {
                                        Task { await app.acceptServerMatch(sm) }
                                        showSheet = false
                                    }.buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            }
                        }
                    }
                    if !hits.isEmpty {
                        Section("\(hits.count) people would be notified") {
                            Text("These users are Open near your origin and their destination fits your comfort range.")
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

    // MARK: - Intent detail

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
                Section {
                    Button {
                        RideHailing.openUberUniversal(from: app.myOrigin, to: i.rider.destination)
                    } label: {
                        Label("Open Uber to co-rider's destination", systemImage: "car.fill")
                    }
                }
            }
            .navigationTitle(i.rider.name)
            .navigationBarTitleDisplayMode(.inline)
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Color hex helper

private extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default: return nil
        }
        self.init(
            .sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}