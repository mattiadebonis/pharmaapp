import Foundation

enum AppTabRoute: String, Hashable, Codable {
    case oggi
    case prossime
    case statistiche
    case medicine
    case profilo
}

enum AppRoute: String, Codable, Equatable {
    case today
    case todayPurchaseList
    case pharmacy
    case codiceFiscaleFullscreen
    case profile
}
