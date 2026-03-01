import Foundation

public protocol StockRepository {
    func units(for packageId: PackageId) throws -> Int
    func applyDelta(_ delta: Int, for packageId: PackageId) throws -> Int
    func setUnits(_ units: Int, for packageId: PackageId) throws
}
