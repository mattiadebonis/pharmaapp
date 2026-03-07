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

    func isFavoriteMedicine(id: UUID) -> Bool {
        favoriteMedicineIDs.contains(id)
    }

    func isFavoriteCabinet(id: UUID) -> Bool {
        favoriteCabinetIDs.contains(id)
    }

    func toggleFavoriteMedicine(id: UUID) {
        let shouldFavorite = !isFavoriteMedicine(id: id)
        setFavoriteMedicine(id: id, favorite: shouldFavorite)
    }

    func toggleFavoriteCabinet(id: UUID) {
        let shouldFavorite = !isFavoriteCabinet(id: id)
        setFavoriteCabinet(id: id, favorite: shouldFavorite)
    }

    func setFavoriteMedicine(id: UUID, favorite: Bool) {
        if favorite {
            favoriteMedicineIDs.insert(id)
        } else {
            favoriteMedicineIDs.remove(id)
        }
        persist()
    }

    func setFavoriteCabinet(id: UUID, favorite: Bool) {
        if favorite {
            favoriteCabinetIDs.insert(id)
        } else {
            favoriteCabinetIDs.remove(id)
        }
        persist()
    }

    func isFavorite(_ medicine: Medicine) -> Bool {
        isFavoriteMedicine(id: medicine.id)
    }

    func isFavorite(_ entry: MedicinePackage) -> Bool {
        isFavorite(entry.medicine)
    }

    func isFavorite(_ cabinet: Cabinet) -> Bool {
        isFavoriteCabinet(id: cabinet.id)
    }

    func toggleFavorite(_ medicine: Medicine) {
        toggleFavoriteMedicine(id: medicine.id)
    }

    func toggleFavorite(_ entry: MedicinePackage) {
        toggleFavorite(entry.medicine)
    }

    func toggleFavorite(_ cabinet: Cabinet) {
        toggleFavoriteCabinet(id: cabinet.id)
    }

    func setFavorite(_ medicine: Medicine, favorite: Bool) {
        setFavoriteMedicine(id: medicine.id, favorite: favorite)
    }

    func setFavorite(_ entry: MedicinePackage, favorite: Bool) {
        setFavorite(entry.medicine, favorite: favorite)
    }

    func setFavorite(_ cabinet: Cabinet, favorite: Bool) {
        setFavoriteCabinet(id: cabinet.id, favorite: favorite)
    }

    private func persist() {
        let medicineIDs = favoriteMedicineIDs.map { $0.uuidString }
        defaults.set(medicineIDs, forKey: Self.medicineKey)
        let cabinetIDs = favoriteCabinetIDs.map { $0.uuidString }
        defaults.set(cabinetIDs, forKey: Self.cabinetKey)
    }
}
