import Foundation

@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTabRoute = .oggi
    @Published var pendingRoute: AppRoute?

    private let routeStore: PendingAppRouteStoring

    init(routeStore: PendingAppRouteStoring = PendingAppRouteStore()) {
        self.routeStore = routeStore
    }

    func open(_ route: AppRoute) {
        apply(route)
        pendingRoute = route
        routeStore.save(route: route)
    }

    func consumePendingRouteIfAny() {
        guard let route = routeStore.consumeRoute() else { return }
        apply(route)
        pendingRoute = route
    }

    func markRouteHandled(_ route: AppRoute) {
        guard pendingRoute == route else { return }
        pendingRoute = nil
    }

    private func apply(_ route: AppRoute) {
        switch route {
        case .today, .todayPurchaseList, .pharmacy, .codiceFiscaleFullscreen, .profile:
            selectedTab = .oggi
        }
    }
}
