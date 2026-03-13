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
    let country: CatalogCountry
    let source: String
    let productKey: String
    let familyKey: String?
    let packageKey: String
    let catalogCode: String?
    let availability: CatalogAvailability

    init(
        id: String,
        name: String,
        principle: String,
        requiresPrescription: Bool,
        packageLabel: String,
        units: Int,
        tipologia: String,
        valore: Int32,
        unita: String,
        volume: String,
        country: CatalogCountry = .it,
        source: String = "catalog",
        productKey: String? = nil,
        familyKey: String? = nil,
        packageKey: String? = nil,
        catalogCode: String? = nil,
        availability: CatalogAvailability = .unknown
    ) {
        self.id = id
        self.name = name
        self.principle = principle
        self.requiresPrescription = requiresPrescription
        self.packageLabel = packageLabel
        self.units = units
        self.tipologia = tipologia
        self.valore = valore
        self.unita = unita
        self.volume = volume
        self.country = country
        self.source = source
        self.productKey = productKey ?? "\(country.rawValue):\(source):product:\(id)"
        self.familyKey = familyKey
        self.packageKey = packageKey ?? "\(country.rawValue):\(source):package:\(id)"
        self.catalogCode = catalogCode
        self.availability = availability
    }
}
