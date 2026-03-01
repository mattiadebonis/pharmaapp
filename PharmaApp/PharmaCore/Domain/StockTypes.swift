import Foundation

public enum StockStatus: String, Hashable {
    case ok
    case low
    case critical
    case unknown
}

public struct StockInfo {
    public let packageId: PackageId
    public let units: Int
    public let autonomyDays: Int?
    public let status: StockStatus

    public init(packageId: PackageId, units: Int, autonomyDays: Int?, status: StockStatus) {
        self.packageId = packageId
        self.units = units
        self.autonomyDays = autonomyDays
        self.status = status
    }
}

public struct CabinetSections<T> {
    public let purchase: [T]
    public let oggi: [T]
    public let ok: [T]

    public init(purchase: [T], oggi: [T], ok: [T]) {
        self.purchase = purchase
        self.oggi = oggi
        self.ok = ok
    }
}
