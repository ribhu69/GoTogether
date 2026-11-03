import SwiftUI

@main
struct GoTogetherApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .onAppear {
                    app.location.request()
                    app.loadSavedProfile()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.onboardingFinished {
            TabView {
                MapHomeView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                InboxView()
                    .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
                    .badge(app.unreadCount > 0 ? app.unreadCount : 0)
                TripView()
                    .tabItem { Label("Trip", systemImage: "car.fill") }
                SafetyView()
                    .tabItem { Label("Safety", systemImage: "shield.checkered") }
            }
            .onAppear { app.location.start() }
        } else {
            OnboardingView()
        }
    }
}