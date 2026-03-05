import CoreData

struct CatalogResolvedContext: Identifiable {
    let selection: CatalogSelection
    let medicine: Medicine
    let package: Package
    let entry: MedicinePackage

    var id: NSManagedObjectID { entry.objectID }
}

struct CatalogSelectionResolver {
    private let context: NSManagedObjectContext
    private let repository: CatalogSelectionRepository

    init(
        context: NSManagedObjectContext,
        repository: CatalogSelectionRepository = CatalogSelectionRepository()
    ) {
        self.context = context
        self.repository = repository
    }

    func addToCabinet(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        let resolved = resolveOrCreateContext(for: selection, markInCabinet: true)
        resolved.entry.cabinet = nil
        try saveIfNeeded()
        return resolved
    }

    func prepareTherapy(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        let resolved = resolveOrCreateContext(for: selection, markInCabinet: true)
        resolved.entry.cabinet = nil
        try saveIfNeeded()
        return resolved
    }

    func buyOnePackage(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        let resolved = resolveOrCreateContext(for: selection, markInCabinet: true)
        resolved.entry.cabinet = nil
        try saveIfNeeded()

        let stockService = StockService(context: context)
        guard stockService.createLog(
            type: "purchase",
            medicine: resolved.medicine,
            package: resolved.package,
            operationId: UUID(),
            save: false
        ) != nil else {
            throw CatalogSelectionResolverError.purchasePreparationFailed
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        return resolved
    }

    func resolveOrCreateContext(
        for selection: CatalogSelection,
        markInCabinet: Bool = true
    ) -> CatalogResolvedContext {
        let medicine = existingMedicine(for: selection) ?? createMedicine(from: selection)
        if markInCabinet {
            medicine.in_cabinet = true
        }
        medicine.obbligo_ricetta = medicine.obbligo_ricetta || selection.requiresPrescription

        let package = existingPackage(for: medicine, selection: selection)
            ?? createPackage(for: medicine, selection: selection)
        let entry = existingEntry(for: medicine, package: package)
            ?? createEntry(for: medicine, package: package)

        if markInCabinet {
            entry.cabinet = nil
        }

        return CatalogResolvedContext(
            selection: selection,
            medicine: medicine,
            package: package,
            entry: entry
        )
    }

    func existingContext(for selection: CatalogSelection) -> CatalogResolvedContext? {
        guard let medicine = existingMedicine(for: selection) else { return nil }
        let package = existingPackage(for: medicine, selection: selection) ?? medicine.packages.first
        guard let package else { return nil }
        let entry = existingEntry(for: medicine, package: package)
        guard let entry else { return nil }
        return CatalogResolvedContext(
            selection: selection,
            medicine: medicine,
            package: package,
            entry: entry
        )
    }

    private func existingMedicine(for selection: CatalogSelection) -> Medicine? {
        let request = Medicine.extractMedicines()
        guard let medicines = try? context.fetch(request) else { return nil }

        let identity = repository.identityKey(for: selection)
        if let exact = medicines.first(where: {
            repository.identityKey(name: $0.nome, principle: $0.principio_attivo) == identity
        }) {
            return exact
        }

        let normalizedName = repository.normalizeText(selection.name)
        return medicines.first(where: { repository.normalizeText($0.nome) == normalizedName })
    }

    private func existingPackage(for medicine: Medicine, selection: CatalogSelection) -> Package? {
        medicine.packages.first(where: { packageMatches($0, selection: selection) })
    }

    private func existingEntry(for medicine: Medicine, package: Package) -> MedicinePackage? {
        if let latest = MedicinePackage.latestActiveEntry(for: medicine, package: package, in: context) {
            return latest
        }
        return medicine.medicinePackages?.first(where: { $0.package.objectID == package.objectID })
    }

    private func packageMatches(_ package: Package, selection: CatalogSelection) -> Bool {
        let sameUnits = Int(package.numero) == max(1, selection.units)
        let sameType = repository.normalizeText(package.tipologia) == repository.normalizeText(selection.tipologia)
        let sameValue = package.valore == selection.valore
        let sameUnit = repository.normalizeText(package.unita) == repository.normalizeText(selection.unita)
        let sameVolume = repository.normalizeText(package.volume) == repository.normalizeText(selection.volume)
        return sameUnits && sameType && sameValue && sameUnit && sameVolume
    }

    private func createMedicine(from selection: CatalogSelection) -> Medicine {
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.source_id = medicine.id
        medicine.visibility = "local"
        medicine.nome = selection.name
        medicine.principio_attivo = selection.principle
        medicine.obbligo_ricetta = selection.requiresPrescription
        medicine.in_cabinet = true
        return medicine
    }

    private func createPackage(for medicine: Medicine, selection: CatalogSelection) -> Package {
        let package = Package(context: context)
        package.id = UUID()
        package.source_id = package.id
        package.visibility = "local"
        package.tipologia = selection.tipologia.isEmpty ? "Confezione" : selection.tipologia
        package.numero = Int32(max(1, selection.units))
        package.unita = selection.unita.isEmpty ? "unita" : selection.unita
        package.volume = selection.volume
        package.valore = max(0, selection.valore)
        package.principio_attivo = selection.principle
        package.medicine = medicine
        medicine.addToPackages(package)
        return package
    }

    private func createEntry(for medicine: Medicine, package: Package) -> MedicinePackage {
        let entry = MedicinePackage(context: context)
        entry.id = UUID()
        entry.created_at = Date()
        entry.source_id = entry.id
        entry.visibility = "local"
        entry.medicine = medicine
        entry.package = package
        entry.cabinet = nil
        medicine.addToMedicinePackages(entry)
        return entry
    }

    private func saveIfNeeded() throws {
        if context.hasChanges {
            try context.save()
        }
    }
}

enum CatalogSelectionResolverError: Error {
    case purchasePreparationFailed
}
