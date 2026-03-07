import Foundation

typealias CatalogResolvedContext = SearchCatalogResolvedContext

struct CatalogSelectionResolver {
    private let resolver: CoreDataCatalogSelectionResolver

    init(
        context: AnyObject,
        repository: CatalogSelectionRepository = CatalogSelectionRepository()
    ) {
        self.resolver = CoreDataCatalogSelectionResolver(
            contextObject: context,
            repository: repository
        )
    }

    func addToCabinet(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        try resolver.addToCabinet(selection)
    }

    func prepareTherapy(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        try resolver.prepareTherapy(selection)
    }

    func buyOnePackage(_ selection: CatalogSelection) throws -> CatalogResolvedContext {
        try resolver.buyOnePackage(selection)
    }

    func resolveOrCreateContext(
        for selection: CatalogSelection,
        markInCabinet: Bool = true
    ) -> CatalogResolvedContext {
        resolver.resolveOrCreateContext(for: selection, markInCabinet: markInCabinet)
    }

    func existingContext(for selection: CatalogSelection) -> CatalogResolvedContext? {
        resolver.existingContext(for: selection)
    }
}

enum CatalogSelectionResolverError: Error {
    case purchasePreparationFailed
}
