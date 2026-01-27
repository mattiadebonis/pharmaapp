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
        favoriteMedicineIDs.contains(medicine.id)
    }

    func isFavorite(_ entry: MedicinePackage) -> Bool {
        isFavorite(entry.medicine)
    }

    func isFavorite(_ cabinet: Cabinet) -> Bool {
        favoriteCabinetIDs.contains(cabinet.id)
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
        if favorite {
            favoriteMedicineIDs.insert(medicine.id)
        } else {
            favoriteMedicineIDs.remove(medicine.id)
        }
        persist()
    }

    func setFavorite(_ entry: MedicinePackage, favorite: Bool) {
        setFavorite(entry.medicine, favorite: favorite)
    }

    func setFavorite(_ cabinet: Cabinet, favorite: Bool) {
        if favorite {
            favoriteCabinetIDs.insert(cabinet.id)
        } else {
            favoriteCabinetIDs.remove(cabinet.id)
        }
        persist()
    }

    private func persist() {
        let medicineIDs = favoriteMedicineIDs.map { $0.uuidString }
        defaults.set(medicineIDs, forKey: Self.medicineKey)
        let cabinetIDs = favoriteCabinetIDs.map { $0.uuidString }
        defaults.set(cabinetIDs, forKey: Self.cabinetKey)
    }
}
