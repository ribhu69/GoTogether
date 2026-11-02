import Foundation

enum Mock {
    static let airport = Place(id: "BLR", name: "Kempegowda Airport (BLR)", lat: 13.1986, lon: 77.7066)

    static let places: [Place] = [
        airport,
        Place(id: "hebbal", name: "Hebbal", lat: 13.0358, lon: 77.5970),
        Place(id: "mg", name: "MG Road", lat: 12.9756, lon: 77.6068),
        Place(id: "indira", name: "Indiranagar", lat: 12.9784, lon: 77.6408),
        Place(id: "kora", name: "Koramangala", lat: 12.9352, lon: 77.6245),
        Place(id: "hsr", name: "HSR Layout", lat: 12.9116, lon: 77.6474),
        Place(id: "white", name: "Whitefield", lat: 12.9698, lon: 77.7500),
        Place(id: "marath", name: "Marathahalli", lat: 12.9569, lon: 77.7011),
        Place(id: "ecity", name: "Electronic City", lat: 12.8452, lon: 77.6602),
        Place(id: "yelah", name: "Yelahanka", lat: 13.1007, lon: 77.5963),
        Place(id: "malle", name: "Malleshwaram", lat: 13.0035, lon: 77.5647),
        Place(id: "jaya", name: "Jayanagar", lat: 12.9250, lon: 77.5938),
    ]
}