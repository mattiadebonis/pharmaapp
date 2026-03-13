import Foundation

enum CatalogCountry: String, CaseIterable, Codable, Hashable {
    case it
    case us

    static func fallback(locale: Locale = .autoupdatingCurrent) -> CatalogCountry {
        let region = locale.regionCode?.uppercased() ?? ""
        return region == "US" ? .us : .it
    }
}

enum CatalogAvailability: String, Codable, Hashable {
    case active
    case inactive
    case shortage
    case suspended
    case revoked
    case unknown
}

struct CatalogIngredient: Codable, Hashable {
    let name: String
    let strengthValue: Decimal?
    let strengthUnit: String?
    let strengthText: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case strengthValue = "strength_value"
        case strengthUnit = "strength_unit"
        case strengthText = "strength_text"
    }
}

struct CatalogRegulatory: Codable, Hashable {
    let applicationNumber: String?
    let marketingCategory: String?
    let authorizationType: String?
    let controlledSubstanceSchedule: String?
    let therapeuticPlanRequired: Bool?
    let orphan: Bool?
    let innovative: Bool?
    let leafletAvailable: Bool?
    let smpcAvailable: Bool?

    private enum CodingKeys: String, CodingKey {
        case applicationNumber = "application_number"
        case marketingCategory = "marketing_category"
        case authorizationType = "authorization_type"
        case controlledSubstanceSchedule = "controlled_substance_schedule"
        case therapeuticPlanRequired = "therapeutic_plan_required"
        case orphan
        case innovative
        case leafletAvailable = "leaflet_available"
        case smpcAvailable = "smpc_available"
    }
}

struct CatalogPackage: Codable, Hashable, Identifiable {
    let id: String
    let sourcePackageId: String
    let packageCode: String?
    let displayName: String
    let unitCount: Int?
    let packageType: String?
    let volumeValue: Decimal?
    let volumeUnit: String?
    let strengthText: String?
    let marketed: Bool?
    let marketingStartDate: Date?
    let marketingEndDate: Date?
    let isSample: Bool?
    let requiresPrescription: Bool?
    let reimbursementClass: String?
    let reimbursementText: String?
    let shortageReason: String?
    let shortageStartDate: Date?
    let shortageEndDate: Date?
    let availability: CatalogAvailability
    let sourceMeta: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id
        case sourcePackageId = "source_package_id"
        case packageCode = "package_code"
        case displayName = "display_name"
        case unitCount = "unit_count"
        case packageType = "package_type"
        case volumeValue = "volume_value"
        case volumeUnit = "volume_unit"
        case strengthText = "strength_text"
        case marketed
        case marketingStartDate = "marketing_start_date"
        case marketingEndDate = "marketing_end_date"
        case isSample = "is_sample"
        case requiresPrescription = "requires_prescription"
        case reimbursementClass = "reimbursement_class"
        case reimbursementText = "reimbursement_text"
        case shortageReason = "shortage_reason"
        case shortageStartDate = "shortage_start_date"
        case shortageEndDate = "shortage_end_date"
        case availability
        case sourceMeta = "source_meta"
    }
}

struct CatalogProduct: Codable, Hashable, Identifiable {
    let id: String
    let country: CatalogCountry
    let source: String
    let sourceProductId: String
    let familyId: String?
    let displayName: String
    let brandName: String?
    let genericName: String?
    let activeIngredients: [CatalogIngredient]
    let dosageForm: String?
    let routes: [String]
    let strengthText: String?
    let manufacturerName: String?
    let requiresPrescription: Bool?
    let availability: CatalogAvailability
    let atcCodes: [String]
    let regulatory: CatalogRegulatory
    let packages: [CatalogPackage]
    let sourceMeta: [String: String]

    private enum CodingKeys: String, CodingKey {
        case id
        case country
        case source
        case sourceProductId = "source_product_id"
        case familyId = "family_id"
        case displayName = "display_name"
        case brandName = "brand_name"
        case genericName = "generic_name"
        case activeIngredients = "active_ingredients"
        case dosageForm = "dosage_form"
        case routes
        case strengthText = "strength_text"
        case manufacturerName = "manufacturer_name"
        case requiresPrescription = "requires_prescription"
        case availability
        case atcCodes = "atc_codes"
        case regulatory
        case packages
        case sourceMeta = "source_meta"
    }
}

extension Option {
    var resolvedCatalogCountry: CatalogCountry {
        CatalogCountry(rawValue: (catalog_country ?? "").lowercased()) ?? .fallback()
    }

    var resolvedBusinessCountry: CatalogCountry {
        CatalogCountry(rawValue: (business_country ?? "").lowercased()) ?? resolvedCatalogCountry
    }
}
