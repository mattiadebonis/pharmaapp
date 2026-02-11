import Foundation
import AppIntents

struct MedicineIntentEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Medicinale")
    static var defaultQuery = MedicineIntentQuery()

    let id: String
    let name: String
    let dosage: String?

    var displayRepresentation: DisplayRepresentation {
        if let dosage, !dosage.isEmpty {
            return DisplayRepresentation(
                title: LocalizedStringResource(stringLiteral: name),
                subtitle: LocalizedStringResource(stringLiteral: dosage)
            )
        }
        return DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct MedicineIntentQuery: EntityStringQuery {
    func entities(for identifiers: [MedicineIntentEntity.ID]) async throws -> [MedicineIntentEntity] {
        SiriIntentFacade.shared.medicines(withIDs: identifiers)
    }

    func entities(matching string: String) async throws -> [MedicineIntentEntity] {
        SiriIntentFacade.shared.medicines(matching: string)
    }

    func suggestedEntities() async throws -> [MedicineIntentEntity] {
        SiriIntentFacade.shared.suggestedMedicines()
    }
}
