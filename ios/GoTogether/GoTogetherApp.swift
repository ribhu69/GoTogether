import SwiftUI

@main
struct GoTogetherApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if app.onboarded {
            TabView {
                MapHomeView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                TripView()
                    .tabItem { Label("Trip", systemImage: "car.fill") }
                SafetyView()
                    .tabItem { Label("Safety", systemImage: "shield.checkered") }
            }
        } else {
            OnboardingView()
        }
    }
}
