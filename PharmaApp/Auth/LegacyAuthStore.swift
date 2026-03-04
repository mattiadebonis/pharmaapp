import Foundation

protocol LegacyAuthStoreProtocol {
    func consumeUser() -> AuthUser?
}

struct LegacyAuthStore: LegacyAuthStoreProtocol {
    private let defaults: UserDefaults
    private let storedUserKey: String

    init(
        defaults: UserDefaults = .standard,
        storedUserKey: String = "auth.user"
    ) {
        self.defaults = defaults
        self.storedUserKey = storedUserKey
    }

    func consumeUser() -> AuthUser? {
        defer {
            defaults.removeObject(forKey: storedUserKey)
        }

        guard let data = defaults.data(forKey: storedUserKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: data) else {
            return nil
        }

        return user
    }
}
