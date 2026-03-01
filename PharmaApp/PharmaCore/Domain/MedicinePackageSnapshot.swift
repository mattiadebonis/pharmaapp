import Foundation

public struct MedicinePackageSnapshot: Identifiable, Hashable {
    public let id: UUID
    public let externalKey: String
    public let medicineId: MedicineId
    public let packageId: PackageId
    public let cabinetId: UUID?
    public let medicineName: String
    public let principioAttivo: String?
    public let packageDescription: String
    public let therapyIds: [TherapyId]

    public init(
        id: UUID,
        externalKey: String,
        medicineId: MedicineId,
        packageId: PackageId,
        cabinetId: UUID?,
        medicineName: String,
        principioAttivo: String?,
        packageDescription: String,
        therapyIds: [TherapyId]
    ) {
        self.id = id
        self.externalKey = externalKey
        self.medicineId = medicineId
        self.packageId = packageId
        self.cabinetId = cabinetId
        self.medicineName = medicineName
        self.principioAttivo = principioAttivo
        self.packageDescription = packageDescription
        self.therapyIds = therapyIds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: MedicinePackageSnapshot, rhs: MedicinePackageSnapshot) -> Bool {
        lhs.id == rhs.id
    }
}
