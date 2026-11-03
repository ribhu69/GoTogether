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
    @State private var myRoute: MKRoute?
    @State private var peerRoutes: [String: MKRoute] = [:]
    @State private var showGroupCreate = false  // peerId → route

    private let originSpanKm: Double = 1.0

    var body: some View {
        @Bindable var app = app
        mainContent
            .onAppear { setup(app: app) }
            .onChange(of: app.location.location) { _, _ in onLocChanged() }
            .onChange(of: [app.search.verifiedOnly, app.search.sameGenderOnly]) { _, _ in app.refreshIntents() }
            .onChange(of: searchText) { _, v in performSearch(v) }
            .onChange(of: app.myComfortKm) { _, _ in app.syncIntent() }
            .onChange(of: app.myDest) { _, _ in app.syncIntent(); calculateMyRoute() }
            .onChange(of: app.hasDestination) { _, now in if now { app.refreshIntents(); calculateMyRoute() } }
            .onChange(of: app.peerLocations.count) { _, _ in calculatePeerRoutes() }
            .onChange(of: app.serverIntents.count) { _, _ in calculatePeerRoutes() }
            .task { await pollingLoop() }
            .sheet(isPresented: $showSheet) { sheetContent }
            .sheet(item: $tappedIntent) { intentDetail($0) }
            .sheet(item: $selectedPeer) { PeerChatSheet(peer: $0) }
            .sheet(isPresented: $showRideApps) { rideAppsSheet }
        .sheet(isPresented: $showGroupCreate) { GroupCreateSheet() }
    }

    private func setup(app: AppState) {
        app.location.request()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            app.updateOriginFromLocation()
            recenterOnUser()
            hasInitialCenter = true
        }
        app.refreshIntents()
    }

    private func onLocChanged() {
        app.updateOriginFromLocation()
        if !hasInitialCenter { recenterOnUser(); hasInitialCenter = true }
    }

    private func pollingLoop() async {
        while !Task.isCancelled {
            await app.pollCycle()
            try? await Task.sleep(for: .seconds(1))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .top) {
            GoTogetherMap(position: $position, app: app,
                          myRoute: myRoute, peerRoutes: peerRoutes,
                          openVisible: openVisible,
                          selectedPeer: $selectedPeer, tappedIntent: $tappedIntent,
                          originSpanKm: originSpanKm)
                .safeAreaInset(edge: .bottom) { bottomBar }
            searchOverlay
        }
    }

    // MARK: - Search overlay (broken out for compiler)

    private var searchOverlay: some View {
        VStack(spacing: 0) {
            searchBar
            if isSearching {
                if searchText.isEmpty {
                    quickDestinations
                } else if searchText.count >= 2 {
                    if !searchResults.isEmpty {
                        searchResultsList
                    } else {
                        searchingIndicator
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .adaptiveWidth()
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search destination…", text: $searchText)
                .textFieldStyle(.plain)
                .onTapGesture { isSearching = true }
            if isSearching && searchText.count >= 2 && searchResults.isEmpty {
                ProgressView().scaleEffect(0.7)
            }
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

    private var searchingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Searching…").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 2)
    }

    private var searchResultsList: some View {
        // Dedup: remove results that are already in recent searches
        let recents = app.recentSearches
        let filtered = searchResults.filter { item in
            let name = item.name ?? ""
            let coord = item.placemark.coordinate
            return !recents.contains { r in
                r.name.caseInsensitiveCompare(name) == .orderedSame
                    && abs(r.lat - coord.latitude) < 0.001
                    && abs(r.lon - coord.longitude) < 0.001
            }
        }
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(filtered, id: \.self) { item in
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
                    if item != filtered.last { Divider().padding(.leading, 12) }
                }

                // Show recent matches below search results
                if !filtered.isEmpty, let firstFiltered = filtered.first {
                    let matchingRecents = recents.filter { r in
                        r.name.localizedCaseInsensitiveContains(searchText)
                    }
                    if !matchingRecents.isEmpty {
                        Section {} header: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                                Text("Recent").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12).padding(.top, 8)
                        }
                        ForEach(matchingRecents) { place in
                            Button {
                                app.myDest = place
                                app.hasDestination = true
                                app.addRecentSearch(place)
                                closeSearch()
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(place.name).font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(String(format: "%.1f km", Geo.km(app.myOrigin, place)))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
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
        app.addRecentSearch(app.myDest)
        closeSearch()
    }

    private func closeSearch() {
        searchText = ""
        searchResults = []
        isSearching = false
    }

    // MARK: - Map helpers

    private func peerAnnotationView(_ peer: PeerLocation) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "person.circle.fill")
                    .font(.title2).foregroundStyle(.green)
                if app.unreadChats.contains(peer.id) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                }
            }
            Text(peer.name.components(separatedBy: " ").first ?? peer.name)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
        }
        .onTapGesture { selectedPeer = peer }
    }

    private func intentAnnotationView(_ intent: TravelIntent) -> some View {
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

    private func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> MKRoute? {
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        req.transportType = .automobile
        return await withCheckedContinuation { cont in
            MKDirections(request: req).calculate { response, _ in
                cont.resume(returning: response?.routes.first)
            }
        }
    }

    private func calculateMyRoute() {
        guard app.myDest.id != app.myOrigin.id else { myRoute = nil; return }
        Task {
            let route = await calculateRoute(from: app.myOrigin.coord, to: app.myDest.coord)
            await MainActor.run { myRoute = route }
        }
    }

    private func calculatePeerRoutes() {
        Task {
            var routes: [String: MKRoute] = [:]
            // From peer locations
            for peer in app.peerLocations {
                if let dest = peer.destination?.coord {
                    routes[peer.id] = await calculateRoute(from: peer.coord, to: dest)
                }
            }
            // From open intents
            for intent in app.matchingOpenIntents() {
                if routes[intent.userId] == nil {
                    routes[intent.userId] = await calculateRoute(
                        from: intent.origin.coord, to: intent.rider.destination.coord)
                }
            }
            await MainActor.run { peerRoutes = routes }
        }
    }

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

    private var statusLabel: String {
        if !app.hasDestination {
            return "Pick a destination to find co-riders"
        }
        let n = openVisible.count
        if n > 0 {
            return "Comfort: \(Int(app.myComfortKm)) km · \(n) compatible nearby"
        }
        return "No compatible travelers — try widening comfort range"
    }

    private var quickDestinations: some View {
        @Bindable var app = app
        let recents = app.recentSearches
        return ScrollView {
            VStack(spacing: 0) {
                if recents.isEmpty {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        Text("Search a destination to start — recent picks appear here")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 14)
                } else {
                    ForEach(recents) { place in
                        Button {
                            app.myDest = place
                            app.hasDestination = true
                            app.addRecentSearch(place)
                            closeSearch()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
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
                        if place.id != recents.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
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
                            Text(statusLabel)
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
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
        let recents = app.recentSearches
        return Form {
            if recents.isEmpty {
                Section {
                    Label("Search a destination above — recent picks appear here", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Recent destinations") {
                    ForEach(recents) { place in
                        HStack {
                            Label(place.name, systemImage: "clock.arrow.circlepath")
                            Spacer()
                            if app.myDest.id == place.id {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            app.myDest = place
                            app.hasDestination = true
                            app.addRecentSearch(place)
                            showSheet = false
                        }
                    }
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
                        // Create group button
                        Button { showGroupCreate = true } label: {
                            Label("Start a group with these riders", systemImage: "person.3.fill")
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
                                Button("Share") {
                                    app.requestIntent(i)
                                    showSheet = false
                                }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .disabled(app.activeTrip != nil)

                                Button {
                                    showSheet = false
                                    if let peer = app.peerLocations.first(where: {
                                        $0.id == i.userId
                                    }) {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            selectedPeer = peer
                                        }
                                    }
                                } label: {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
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
                                Text("Pick a destination — you'll automatically be visible. When someone nearby picks theirs, they'll appear here.")
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
                        Text("Scanning for travelers…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "No travelers nearby",
                        systemImage: "person.2.slash",
                        description: Text("Pick a destination to become visible. When someone nearby picks theirs, they'll show up here.")
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
                            Button { showGroupCreate = true } label: {
                                Label("Start a group with these riders", systemImage: "person.3.fill")
                            }
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
                            Button {
                                showSheet = false
                                if let peer = app.peerLocations.first(where: {
                                    $0.id == i.userId
                                }) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        selectedPeer = peer
                                    }
                                }
                            } label: {
                                Image(systemName: "bubble.left.and.bubble.right")
                            }
                            .buttonStyle(.bordered).controlSize(.small)
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
                    Button {
                        tappedIntent = nil  // dismiss this sheet first
                        // Find peer in locations to open chat
                        if let peer = app.peerLocations.first(where: {
                            $0.id == i.userId
                        }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                selectedPeer = peer
                            }
                        }
                    } label: {
                        Label("Chat with \(i.rider.name.components(separatedBy: " ").first ?? i.rider.name)", systemImage: "bubble.left.and.bubble.right")
                    }
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

// MARK: - Extracted Map view (avoids compiler type-check complexity)

struct GoTogetherMap: View {
    @Binding var position: MapCameraPosition
    let app: AppState
    let myRoute: MKRoute?
    let peerRoutes: [String: MKRoute]
    let openVisible: [TravelIntent]
    @Binding var selectedPeer: PeerLocation?
    @Binding var tappedIntent: TravelIntent?
    let originSpanKm: Double

    var body: some View {
        Map(position: $position, interactionModes: .all) {
            UserAnnotation()
            Annotation("You", coordinate: app.myOrigin.coord) {
                ProfileImageView(imageData: app.profileImageData, size: 36,
                                 fallbackIcon: "person.circle.fill", fallbackColor: .blue)
            }
            if app.myDest.id != app.myOrigin.id {
                Annotation("Your destination", coordinate: app.myDest.coord) {
                    Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red)
                }
                if let r = myRoute {
                    MapPolyline(r).stroke(.blue.opacity(0.5), lineWidth: 3)
                }
            }
            MapCircle(center: app.myDest.coord, radius: app.myComfortKm * 1000)
                .foregroundStyle(.orange.opacity(0.15)).mapOverlayLevel(level: .aboveLabels)
            MapCircle(center: app.myOrigin.coord, radius: originSpanKm * 1000)
                .foregroundStyle(.blue.opacity(0.08)).mapOverlayLevel(level: .aboveLabels)
            ForEach(app.peerLocations) { peer in
                Annotation(peer.name, coordinate: peer.coord) {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "person.circle.fill")
                                .font(.title2).foregroundStyle(.green)
                            if app.unreadChats.contains(peer.id) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                            }
                        }
                        Text(peer.name.components(separatedBy: " ").first ?? peer.name)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .onTapGesture { selectedPeer = peer }
                }
            }
            ForEach(app.peerLocations) { peer in
                if let r = peerRoutes[peer.id] {
                    MapPolyline(r).stroke(.green.opacity(0.35), lineWidth: 2)
                }
            }
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
            }
            ForEach(openVisible) { intent in
                if let r = peerRoutes[intent.userId] {
                    MapPolyline(r).stroke(.green.opacity(0.35), lineWidth: 2)
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
    }
}

// MARK: - Group creation sheet

struct GroupCreateSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = "Cab Share"
    @State private var selectedIds: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section("Group name") {
                    TextField("Group name", text: $groupName)
                }
                Section("Select riders") {
                    let candidates = app.matchingOpenIntents()
                    if candidates.isEmpty {
                        Text("No riders nearby — pick a destination first").foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { intent in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(intent.rider.name).font(.headline)
                                Text("→ \(intent.rider.destination.name)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedIds.contains(intent.userId) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedIds.contains(intent.userId) {
                                selectedIds.remove(intent.userId)
                            } else {
                                selectedIds.insert(intent.userId)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        app.createGroup(name: groupName, memberIds: Array(selectedIds))
                        dismiss()
                    }
                    .disabled(selectedIds.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { app.fetchMyGroups() }
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