import Foundation

protocol PendingAppRouteStoring {
    func save(route: AppRoute)
    func loadRoute() -> AppRoute?
    func clearRoute()
    func consumeRoute() -> AppRoute?
}

struct PendingAppRouteStore: PendingAppRouteStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "pharmaapp.pending_route") {
        self.defaults = defaults
        self.key = key
    }

    func save(route: AppRoute) {
        guard let data = try? JSONEncoder().encode(route) else { return }
        defaults.set(data, forKey: key)
    }

    func loadRoute() -> AppRoute? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppRoute.self, from: data)
    }

    func clearRoute() {
        defaults.removeObject(forKey: key)
    }

    func consumeRoute() -> AppRoute? {
        let route = loadRoute()
        clearRoute()
        return route
    }
}
