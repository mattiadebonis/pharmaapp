import Foundation
import CoreData

final class CoreDataMedicinePackageRepository: MedicinePackageRepository {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() throws -> [MedicinePackageSnapshot] {
        let request = MedicinePackage.extractEntries()
        let entries = try context.fetch(request)
        return entries.map { makeSnapshot(from: $0) }
    }

    func fetchEntries(cabinetId: UUID) throws -> [MedicinePackageSnapshot] {
        let request: NSFetchRequest<MedicinePackage> = MedicinePackage.fetchRequest() as! NSFetchRequest<MedicinePackage>
        request.predicate = NSPredicate(format: "cabinet.id == %@", cabinetId as CVarArg)
        let entries = try context.fetch(request)
        return entries.map { makeSnapshot(from: $0) }
    }

    private func makeSnapshot(from entry: MedicinePackage) -> MedicinePackageSnapshot {
        let therapyIds: [TherapyId] = {
            if let therapies = entry.therapies, !therapies.isEmpty {
                return therapies.map { TherapyId($0.id) }
            }
            let all = entry.medicine.therapies ?? []
            return all.filter { $0.package.objectID == entry.package.objectID }
                .map { TherapyId($0.id) }
        }()

        return MedicinePackageSnapshot(
            id: entry.id,
            externalKey: entry.objectID.uriRepresentation().absoluteString,
            medicineId: MedicineId(entry.medicine.id),
            packageId: PackageId(entry.package.id),
            cabinetId: entry.cabinet?.id,
            medicineName: entry.medicine.nome,
            principioAttivo: entry.medicine.principio_attivo,
            packageDescription: entry.package.denominazione_package ?? "",
            therapyIds: therapyIds
        )
    }
}
