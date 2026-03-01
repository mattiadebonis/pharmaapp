import Foundation

public protocol TherapyRepository {
    func fetchTherapies(for medicineId: MedicineId) throws -> [TherapySnapshot]
    func fetchTherapy(id: TherapyId) throws -> TherapySnapshot?
}
