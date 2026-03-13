import Foundation
import Supabase

enum CatalogGatewayError: LocalizedError {
    case notConfigured
    case invalidCountry

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Configurazione Supabase mancante. Imposta SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY."
        case .invalidCountry:
            return "Paese catalogo non valido."
        }
    }
}

private struct SupabaseConfiguration {
    let url: URL
    let publishableKey: String

    static func load(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> SupabaseConfiguration? {
        let rawURL = sanitizedValue(
            processInfo.environment["SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        )
        let rawKey = sanitizedValue(
            processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
        )

        guard let rawURL,
              let url = URL(string: rawURL),
              let rawKey else {
            return nil
        }

        return SupabaseConfiguration(url: url, publishableKey: rawKey)
    }

    private static func sanitizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SupabaseClientFactory {
    private static var cachedClient: SupabaseClient?
    private static var cachedConfiguration: SupabaseConfiguration?

    static func client() throws -> SupabaseClient {
        guard let configuration = SupabaseConfiguration.load() else {
            throw CatalogGatewayError.notConfigured
        }

        if let cachedClient,
           let cachedConfiguration,
           cachedConfiguration.url == configuration.url,
           cachedConfiguration.publishableKey == configuration.publishableKey {
            return cachedClient
        }

        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        cachedConfiguration = configuration
        cachedClient = client
        return client
    }
}

private struct CatalogSearchRow: Decodable {
    let country: CatalogCountry
    let source: String
    let productId: String
    let packageId: String
    let familyId: String?
    let displayName: String
    let genericName: String?
    let principle: String?
    let requiresPrescription: Bool?
    let packageLabel: String
    let units: Int?
    let tipologia: String?
    let valore: Int32?
    let unita: String?
    let volume: String?
    let availability: CatalogAvailability?
    let catalogCode: String?

    private enum CodingKeys: String, CodingKey {
        case country
        case source
        case productId = "product_id"
        case packageId = "package_id"
        case familyId = "family_id"
        case displayName = "display_name"
        case genericName = "generic_name"
        case principle
        case requiresPrescription = "requires_prescription"
        case packageLabel = "package_label"
        case units
        case tipologia
        case valore
        case unita
        case volume
        case availability
        case catalogCode = "catalog_code"
    }
}

final class SharedCatalogGateway: CatalogGateway {
    func searchCatalog(
        country: CatalogCountry,
        query: String,
        limit: Int = 40
    ) async throws -> [CatalogSelection] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        let client = try SupabaseClientFactory.client()
        let pattern = ilikePattern(for: trimmedQuery)
        let queryBuilder = client
            .from("catalog_search_v1")
            .select()
            .eq("country", value: country.rawValue)
            .or(
                [
                    "display_name.ilike.\(pattern)",
                    "generic_name.ilike.\(pattern)",
                    "principle.ilike.\(pattern)",
                    "package_label.ilike.\(pattern)"
                ].joined(separator: ",")
            )
            .limit(limit)

        let rows: [CatalogSearchRow] = try await queryBuilder.execute().value
        return rows.map { row in
            CatalogSelection(
                id: row.packageId,
                name: row.displayName,
                principle: row.principle ?? row.genericName ?? row.displayName,
                requiresPrescription: row.requiresPrescription ?? false,
                packageLabel: row.packageLabel,
                units: max(1, row.units ?? 1),
                tipologia: row.tipologia ?? row.packageLabel,
                valore: row.valore ?? 0,
                unita: row.unita ?? "",
                volume: row.volume ?? "",
                country: row.country,
                source: row.source,
                productKey: row.productId,
                familyKey: row.familyId,
                packageKey: row.packageId,
                catalogCode: row.catalogCode,
                availability: row.availability ?? .unknown
            )
        }
    }

    func fetchCatalogProduct(
        country: CatalogCountry,
        productId: String
    ) async throws -> CatalogProduct {
        let client = try SupabaseClientFactory.client()
        return try await client
            .rpc(
                "fetch_catalog_product_v1",
                params: [
                    "country": country.rawValue,
                    "product_id": productId
                ]
            )
            .single()
            .execute()
            .value
    }

    func fetchCatalogPackage(
        country: CatalogCountry,
        packageId: String
    ) async throws -> CatalogPackage {
        let client = try SupabaseClientFactory.client()
        return try await client
            .rpc(
                "fetch_catalog_package_v1",
                params: [
                    "country": country.rawValue,
                    "package_id": packageId
                ]
            )
            .single()
            .execute()
            .value
    }

    private func ilikePattern(for query: String) -> String {
        let cleaned = query
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "*", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "*\(cleaned)*"
    }
}
