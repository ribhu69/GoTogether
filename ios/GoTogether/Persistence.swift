import Foundation

/// Lightweight persistence for user preferences and saved addresses.
enum Persistence {
    private static let defaults = UserDefaults.standard

    // MARK: - Saved home address

    static var homeAddress: Place? {
        get {
            guard let data = defaults.data(forKey: "homeAddress"),
                  let p = try? JSONDecoder().decode(StoredPlace.self, from: data)
            else { return nil }
            return Place(id: "home", name: p.name, lat: p.lat, lon: p.lon)
        }
        set {
            if let p = newValue {
                let sp = StoredPlace(name: p.name, lat: p.lat, lon: p.lon)
                defaults.set(try? JSONEncoder().encode(sp), forKey: "homeAddress")
            } else {
                defaults.removeObject(forKey: "homeAddress")
            }
        }
    }

    // MARK: - Onboarding skip

    static var onboardingComplete: Bool {
        get { defaults.bool(forKey: "onboardingComplete") }
        set { defaults.set(newValue, forKey: "onboardingComplete") }
    }

    static var onboardingFinished: Bool {
        get { defaults.bool(forKey: "onboardingFinished") }
        set { defaults.set(newValue, forKey: "onboardingFinished") }
    }

    static var savedName: String {
        get { defaults.string(forKey: "savedName") ?? "" }
        set { defaults.set(newValue, forKey: "savedName") }
    }

    static var savedPhone: String {
        get { defaults.string(forKey: "savedPhone") ?? "" }
        set { defaults.set(newValue, forKey: "savedPhone") }
    }

    static var savedGender: String {
        get { defaults.string(forKey: "savedGender") ?? "Female" }
        set { defaults.set(newValue, forKey: "savedGender") }
    }

    static var savedEmergencyName: String {
        get { defaults.string(forKey: "savedEmergencyName") ?? "" }
        set { defaults.set(newValue, forKey: "savedEmergencyName") }
    }

    static var savedEmergencyPhone: String {
        get { defaults.string(forKey: "savedEmergencyPhone") ?? "" }
        set { defaults.set(newValue, forKey: "savedEmergencyPhone") }
    }

    static var savedPhoneVerified: Bool {
        get { defaults.bool(forKey: "savedPhoneVerified") }
        set { defaults.set(newValue, forKey: "savedPhoneVerified") }
    }

    static var savedIdVerified: Bool {
        get { defaults.bool(forKey: "savedIdVerified") }
        set { defaults.set(newValue, forKey: "savedIdVerified") }
    }

    static var savedIdType: String {
        get { defaults.string(forKey: "savedIdType") ?? "Aadhaar" }
        set { defaults.set(newValue, forKey: "savedIdType") }
    }

    static var savedIdLast4: String {
        get { defaults.string(forKey: "savedIdLast4") ?? "" }
        set { defaults.set(newValue, forKey: "savedIdLast4") }
    }

    // MARK: - Recent searches

    static var recentSearches: [Place] {
        get {
            guard let data = defaults.data(forKey: "recentSearches"),
                  let places = try? JSONDecoder().decode([StoredPlace].self, from: data)
            else { return [] }
            return places.enumerated().map { i, p in
                Place(id: "recent-\(i)-\(p.name)", name: p.name, lat: p.lat, lon: p.lon)
            }
        }
        set {
            let stored = newValue.map { StoredPlace(name: $0.name, lat: $0.lat, lon: $0.lon) }
            defaults.set(try? JSONEncoder().encode(stored), forKey: "recentSearches")
        }
    }
}

private struct StoredPlace: Codable {
    let name: String
    let lat: Double
    let lon: Double
}