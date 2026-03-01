import Foundation

public protocol MedicineRepository {
    func fetchAllInCabinet() throws -> [MedicineSnapshot]
    func fetchMedicine(id: MedicineId) throws -> MedicineSnapshot?
    func fetchMedicineSnapshots(ids: [MedicineId]) throws -> [MedicineSnapshot]
}
