import Foundation
import Testing
@testable import PharmaApp

@MainActor
private final class RefillRouteStoreFake: PendingAppRouteStoring {
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
private final class RefillDismissHandlerFake: RefillLiveActivityDismissHandling {
    var dismissCalls = 0

    func dismissCurrentActivity(reason: String) async {
        let _ = reason
        dismissCalls += 1
    }
}

@MainActor
struct RefillIntentTests {
    @Test func openPurchaseListIntentQueuesTodayPurchaseRoute() async throws {
        let fakeStore = RefillRouteStoreFake()
        let previousStore = OpenPurchaseListIntent.routeStore
        OpenPurchaseListIntent.routeStore = fakeStore
        defer { OpenPurchaseListIntent.routeStore = previousStore }

        _ = try await OpenPurchaseListIntent().perform()

        #expect(fakeStore.savedRoute == .pharmacy)
    }

    @Test func dismissRefillIntentCallsDismissHandler() async throws {
        let fakeHandler = RefillDismissHandlerFake()
        let previousHandler = DismissRefillActivityIntent.dismissHandler
        DismissRefillActivityIntent.dismissHandler = fakeHandler
        defer { DismissRefillActivityIntent.dismissHandler = previousHandler }

        _ = try await DismissRefillActivityIntent().perform()

        #expect(fakeHandler.dismissCalls == 1)
    }
}
