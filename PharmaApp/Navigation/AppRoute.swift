import Foundation

enum AppTabRoute: String, Hashable, Codable {
    case oggi
    case medicine
}

enum AppRoute: String, Codable, Equatable {
    case today
    case todayPurchaseList
    case pharmacy
    case codiceFiscaleFullscreen
    case profile
}
