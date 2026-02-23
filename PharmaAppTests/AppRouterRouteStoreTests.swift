import XCTest
@testable import PharmaApp

final class AppRouterRouteStoreTests: XCTestCase {
    func testPendingRouteStorePersistAndConsume() {
        let suite = "AppRouterRouteStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Missing custom suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)

        let store = PendingAppRouteStore(defaults: defaults, key: "pending.route.test")
        store.save(route: .pharmacy)

        XCTAssertEqual(store.loadRoute(), .pharmacy)
        XCTAssertEqual(store.consumeRoute(), .pharmacy)
        XCTAssertNil(store.loadRoute())

        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testRouterConsumePendingRouteApreTabECaricaRoute() {
        let fakeStore = FakeRouteStore(route: .pharmacy)
        let router = AppRouter(routeStore: fakeStore)

        router.consumePendingRouteIfAny()

        XCTAssertEqual(router.selectedTab, .medicine)
        XCTAssertEqual(router.pendingRoute, .pharmacy)

        router.markRouteHandled(.pharmacy)
        XCTAssertNil(router.pendingRoute)
    }

    @MainActor
    func testRouterOpenSalvaRoute() {
        let fakeStore = FakeRouteStore()
        let router = AppRouter(routeStore: fakeStore)

        router.open(.profile)

        XCTAssertEqual(fakeStore.savedRoute, .profile)
        XCTAssertEqual(router.selectedTab, .profilo)
        XCTAssertEqual(router.pendingRoute, .profile)
    }
}

private final class FakeRouteStore: PendingAppRouteStoring {
    private(set) var savedRoute: AppRoute?
    private var routeToConsume: AppRoute?

    init(route: AppRoute? = nil) {
        self.routeToConsume = route
    }

    func save(route: AppRoute) {
        savedRoute = route
        routeToConsume = route
    }

    func loadRoute() -> AppRoute? {
        routeToConsume
    }

    func clearRoute() {
        routeToConsume = nil
    }

    func consumeRoute() -> AppRoute? {
        let route = routeToConsume
        routeToConsume = nil
        return route
    }
}
