import Foundation

final class AppDataProviderRegistry {
    static let shared = AppDataProviderRegistry()

    var provider: (any AppDataProvider)?

    private init() {}
}
