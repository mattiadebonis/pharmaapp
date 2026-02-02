import Foundation

struct CatalogSelection: Identifiable, Hashable {
    let id: String
    let name: String
    let principle: String
    let requiresPrescription: Bool
    let packageLabel: String
    let units: Int
    let tipologia: String
    let valore: Int32
    let unita: String
    let volume: String
}
