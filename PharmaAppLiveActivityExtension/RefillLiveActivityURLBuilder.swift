import Foundation

enum RefillLiveActivityURLBuilder {
    enum Action: String {
        case openPurchaseList = "open-purchase-list"
        case openHealthCard = "open-health-card"
        case dismissRefill = "dismiss-refill"
    }

    static func actionURL(_ action: Action) -> URL {
        var components = URLComponents()
        components.scheme = "pharmaapp"
        components.host = "live-activity"
        components.queryItems = [
            URLQueryItem(name: "action", value: action.rawValue)
        ]
        return components.url ?? URL(string: "pharmaapp://today")!
    }

    static func mapsURL(latitude: Double, longitude: Double, name: String) -> URL {
        var components = URLComponents(string: "https://maps.apple.com")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name)
        ]
        return components?.url ?? URL(string: "https://maps.apple.com")!
    }
}
