import Foundation

enum AppTabRoute: String, Hashable, Codable {
    case medicine
    case profilo
    case search
}

enum AppRoute: String, Codable, Equatable {
    case today
    case todayPurchaseList
    case pharmacy
    case codiceFiscaleFullscreen
    case profile
    case scan
    case addMedicine
}
