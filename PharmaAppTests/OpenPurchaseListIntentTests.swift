import Foundation
import Testing
@testable import PharmaApp

@MainActor
private final class OpenPurchaseListRouteStoreFake: PendingAppRouteStoring {
    var savedRoute: AppRoute?

    func save(route: AppRoute) {
        savedRoute = route
    }

    func loadRoute() -> AppRoute? {
        savedRoute
    }

    func clearRoute() {
        savedRoute = nil
    }

    func consumeRoute() -> AppRoute? {
        let value = savedRoute
        savedRoute = nil
        return value
    }
}

@MainActor
struct OpenPurchaseListIntentTests {
    @Test func openPurchaseListIntentQueuesTodayPurchaseRoute() async throws {
        let fakeStore = OpenPurchaseListRouteStoreFake()
        let previousStore = OpenPurchaseListIntent.routeStoreOverride
        OpenPurchaseListIntent.routeStoreOverride = fakeStore
        defer { OpenPurchaseListIntent.routeStoreOverride = previousStore }

        _ = try await OpenPurchaseListIntent().perform()

        #expect(fakeStore.savedRoute == .pharmacy)
    }
}
