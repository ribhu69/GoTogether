import Foundation
import UIKit

/// Opens ride-hailing apps with pre-filled pickup and drop-off coordinates.
enum RideHailing {

    struct App {
        let name: String
        let color: String        // hex for tint
        let scheme: String       // URL scheme
        let appStoreId: String   // fallback App Store ID
    }

    static let apps: [App] = [
        App(name: "Uber",
            color: "#000000",
            scheme: "uber://",
            appStoreId: "368677368"),
        App(name: "Ola",
            color: "#9ACD32",
            scheme: "olacabs://",
            appStoreId: "539179365"),
        App(name: "Rapido",
            color: "#FF6B00",
            scheme: "rapido://",
            appStoreId: "1198464606"),
    ]

    /// Open the ride app with from/to coordinates.
    /// Falls back to App Store if the app isn't installed.
    static func open(_ app: App, from: Place, to: Place) {
        let fromName = from.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let toName = to.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let urlStr: String

        switch app.name {
        case "Uber":
            // Uber deep link: uber://?action=setPickup&pickup[latitude]=...&pickup[longitude]=...&dropoff[latitude]=...&dropoff[longitude]=...
            urlStr = "\(app.scheme)?action=setPickup&pickup[latitude]=\(from.lat)&pickup[longitude]=\(from.lon)&pickup[nickname]=\(fromName)&dropoff[latitude]=\(to.lat)&dropoff[longitude]=\(to.lon)&dropoff[nickname]=\(toName)"
        case "Ola":
            // Ola deep link
            urlStr = "\(app.scheme)?pickup_lat=\(from.lat)&pickup_lng=\(from.lon)&drop_lat=\(to.lat)&drop_lng=\(to.lon)"
        case "Rapido":
            // Rapido deep link
            urlStr = "\(app.scheme)?pickup_lat=\(from.lat)&pickup_lng=\(from.lon)&drop_lat=\(to.lat)&drop_lng=\(to.lon)"
        default:
            urlStr = ""
        }

        guard let url = URL(string: urlStr), UIApplication.shared.canOpenURL(url) else {
            // Fallback: open App Store
            if let storeURL = URL(string: "https://apps.apple.com/app/id\(app.appStoreId)") {
                UIApplication.shared.open(storeURL)
            }
            return
        }
        UIApplication.shared.open(url)
    }

    /// Launch Uber with a universal / web fallback (most reliable).
    static func openUberUniversal(from: Place, to: Place) {
        let clientId = ""  // optional: register at developer.uber.com for deep-link attribution
        var components = URLComponents(string: "https://m.uber.com/ul/")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "setPickup"),
            URLQueryItem(name: "pickup[latitude]", value: "\(from.lat)"),
            URLQueryItem(name: "pickup[longitude]", value: "\(from.lon)"),
            URLQueryItem(name: "pickup[nickname]", value: from.name),
            URLQueryItem(name: "dropoff[latitude]", value: "\(to.lat)"),
            URLQueryItem(name: "dropoff[longitude]", value: "\(to.lon)"),
            URLQueryItem(name: "dropoff[nickname]", value: to.name),
        ]
        if !clientId.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "client_id", value: clientId))
        }
        UIApplication.shared.open(components.url!)
    }
}