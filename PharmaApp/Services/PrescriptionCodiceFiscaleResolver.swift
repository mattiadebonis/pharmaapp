import Foundation
import CoreData

struct PrescriptionCFEntry: Identifiable {
    let person: Person
    let codiceFiscale: String
    let medicineNames: [String]

    var id: NSManagedObjectID { person.objectID }

    var personDisplayName: String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }
}

@MainActor
struct PrescriptionCodiceFiscaleResolver {
    func entriesForRxAndLowStock(in context: NSManagedObjectContext) -> [PrescriptionCFEntry] {
        let request = Medicine.extractMedicines()
        let medicines = (try? context.fetch(request)) ?? []
        return entriesForRxAndLowStock(in: context, medicines: medicines)
    }

    func entriesForRxAndLowStock(in context: NSManagedObjectContext, medicines: [Medicine]) -> [PrescriptionCFEntry] {
        let option = Option.current(in: context)
        let recurrenceManager = RecurrenceManager(context: context)

        struct Bucket {
            let person: Person
            let codiceFiscale: String
            var medicineNames: Set<String>
        }

        var buckets: [NSManagedObjectID: Bucket] = [:]

        for medicine in medicines {
            guard medicine.obbligo_ricetta else { continue }
            guard shouldIncludeForLowStock(medicine, option: option, recurrenceManager: recurrenceManager) else { continue }
            guard let therapies = medicine.therapies, !therapies.isEmpty else { continue }

            let medicineName = normalizedMedicineName(medicine.nome)
            for therapy in therapies {
                let person = therapy.person
                guard let codice = normalizedCodiceFiscale(person.codice_fiscale) else { continue }

                if var existing = buckets[person.objectID] {
                    existing.medicineNames.insert(medicineName)
                    buckets[person.objectID] = existing
                } else {
                    buckets[person.objectID] = Bucket(
                        person: person,
                        codiceFiscale: codice,
                        medicineNames: [medicineName]
                    )
                }
            }
        }

        return buckets.values
            .map { bucket in
                PrescriptionCFEntry(
                    person: bucket.person,
                    codiceFiscale: bucket.codiceFiscale,
                    medicineNames: bucket.medicineNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                )
            }
            .sorted { lhs, rhs in
                lhs.personDisplayName.localizedCaseInsensitiveCompare(rhs.personDisplayName) == .orderedAscending
            }
    }

    private func shouldIncludeForLowStock(
        _ medicine: Medicine,
        option: Option?,
        recurrenceManager: RecurrenceManager
    ) -> Bool {
        guard let therapies = medicine.therapies, !therapies.isEmpty else { return false }

        var totalLeft: Double = 0
        var dailyUsage: Double = 0

        for therapy in therapies {
            totalLeft += Double(therapy.leftover())
            dailyUsage += therapy.stimaConsumoGiornaliero(recurrenceManager: recurrenceManager)
        }

        if totalLeft <= 0 {
            return true
        }

        guard dailyUsage > 0 else {
            return false
        }

        let threshold = Double(medicine.stockThreshold(option: option))
        let coverageDays = totalLeft / dailyUsage
        return coverageDays < threshold
    }

    private func normalizedMedicineName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        return trimmed.lowercased().localizedCapitalized
    }

    private func normalizedCodiceFiscale(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = CodiceFiscaleValidator.normalize(raw)
        guard CodiceFiscaleValidator.isValid(normalized) else { return nil }
        return normalized
    }
}
