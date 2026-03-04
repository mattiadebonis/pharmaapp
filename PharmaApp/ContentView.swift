import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var moc
    @EnvironmentObject private var appRouter: AppRouter
    @State private var isGlobalCodiceFiscalePresented = false
    @State private var globalCodiceFiscaleEntries: [PrescriptionCFEntry] = []

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .fullScreenCover(isPresented: $isGlobalCodiceFiscalePresented) {
            CodiceFiscaleFullscreenView(entries: globalCodiceFiscaleEntries) {
                isGlobalCodiceFiscalePresented = false
            }
        }
        .onAppear {
            appRouter.consumePendingRouteIfAny()
            handleGlobalRoute(appRouter.pendingRoute)
        }
        .onChange(of: appRouter.pendingRoute) { route in
            handleGlobalRoute(route)
        }
    }

    private func handleGlobalRoute(_ route: AppRoute?) {
        guard let route else { return }
        switch route {
        case .profile:
            appRouter.markRouteHandled(route)
        case .codiceFiscaleFullscreen:
            globalCodiceFiscaleEntries = PrescriptionCodiceFiscaleResolver().entriesForRxAndLowStock(in: moc)
            isGlobalCodiceFiscalePresented = true
            appRouter.markRouteHandled(route)
        case .pharmacy:
            appRouter.markRouteHandled(route)
        case .scan, .addMedicine:
            break
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
        TabView(selection: $appRouter.selectedTab) {
            Tab("Armadietto", systemImage: "pills", value: AppTabRoute.medicine) {
                NavigationStack {
                    CabinetView()
                }
            }
            Tab("Profilo", systemImage: "person.crop.circle", value: AppTabRoute.profilo) {
                NavigationStack {
                    ProfileView(showsDoneButton: false)
                        .navigationTitle("Profilo")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            Tab(
                "Cerca",
                systemImage: "magnifyingglass",
                value: AppTabRoute.search,
                role: .search
            ) {
                NavigationStack {
                    GlobalSearchView()
                        .navigationTitle("Cerca")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $appRouter.selectedTab) {
            NavigationStack {
                CabinetView()
            }
            .tabItem {
                Label("Armadietto", systemImage: "pills")
            }
            .tag(AppTabRoute.medicine)

            NavigationStack {
                ProfileView(showsDoneButton: false)
                    .navigationTitle("Profilo")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Profilo", systemImage: "person.crop.circle")
            }
            .tag(AppTabRoute.profilo)

            NavigationStack {
                GlobalSearchView()
                    .navigationTitle("Cerca")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Cerca", systemImage: "magnifyingglass")
            }
            .tag(AppTabRoute.search)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environmentObject(AppRouter())
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
