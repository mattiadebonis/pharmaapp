import CoreData
import Foundation
import SwiftUI

@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favoriteMedicineIDs: Set<UUID>
    @Published private(set) var favoriteCabinetIDs: Set<UUID>

    private let defaults: UserDefaults
    private static let medicineKey = "pharmaapp.favoriteMedicineIDs"
    private static let cabinetKey = "pharmaapp.favoriteCabinetIDs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: Self.medicineKey) as? [String] {
            self.favoriteMedicineIDs = Set(stored.compactMap { UUID(uuidString: $0) })
        } else {
            self.favoriteMedicineIDs = []
        }
        if let storedCabinets = defaults.array(forKey: Self.cabinetKey) as? [String] {
            self.favoriteCabinetIDs = Set(storedCabinets.compactMap { UUID(uuidString: $0) })
        } else {
            self.favoriteCabinetIDs = []
        }
    }

    func isFavorite(_ medicine: Medicine) -> Bool {
        guard let id = safeMedicineId(medicine) else { return false }
        return favoriteMedicineIDs.contains(id)
    }

    func isFavorite(_ entry: MedicinePackage) -> Bool {
        isFavorite(entry.medicine)
    }

    func isFavorite(_ cabinet: Cabinet) -> Bool {
        guard let id = safeCabinetId(cabinet) else { return false }
        return favoriteCabinetIDs.contains(id)
    }

    func toggleFavorite(_ medicine: Medicine) {
        let shouldFavorite = !isFavorite(medicine)
        setFavorite(medicine, favorite: shouldFavorite)
    }

    func toggleFavorite(_ entry: MedicinePackage) {
        toggleFavorite(entry.medicine)
    }

    func toggleFavorite(_ cabinet: Cabinet) {
        let shouldFavorite = !isFavorite(cabinet)
        setFavorite(cabinet, favorite: shouldFavorite)
    }

    func setFavorite(_ medicine: Medicine, favorite: Bool) {
        guard let id = safeMedicineId(medicine) else { return }
        if favorite {
            favoriteMedicineIDs.insert(id)
        } else {
            favoriteMedicineIDs.remove(id)
        }
        persist()
    }

    func setFavorite(_ entry: MedicinePackage, favorite: Bool) {
        setFavorite(entry.medicine, favorite: favorite)
    }

    func setFavorite(_ cabinet: Cabinet, favorite: Bool) {
        guard let id = safeCabinetId(cabinet) else { return }
        if favorite {
            favoriteCabinetIDs.insert(id)
        } else {
            favoriteCabinetIDs.remove(id)
        }
        persist()
    }

    private func safeMedicineId(_ medicine: Medicine) -> UUID? {
        guard !medicine.isDeleted else { return nil }
        return medicine.value(forKey: "id") as? UUID
    }

    private func safeCabinetId(_ cabinet: Cabinet) -> UUID? {
        guard !cabinet.isDeleted else { return nil }
        return cabinet.value(forKey: "id") as? UUID
    }

    private func persist() {
        let medicineIDs = favoriteMedicineIDs.map { $0.uuidString }
        defaults.set(medicineIDs, forKey: Self.medicineKey)
        let cabinetIDs = favoriteCabinetIDs.map { $0.uuidString }
        defaults.set(cabinetIDs, forKey: Self.cabinetKey)
    }
}
