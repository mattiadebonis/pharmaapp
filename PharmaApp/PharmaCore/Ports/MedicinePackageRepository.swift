import Foundation

public protocol MedicinePackageRepository {
    func fetchAll() throws -> [MedicinePackageSnapshot]
    func fetchEntries(cabinetId: UUID) throws -> [MedicinePackageSnapshot]
}
