import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appDataStore: AppDataStore
    @State private var isGlobalCodiceFiscalePresented = false
    @State private var globalCodiceFiscaleEntries: [PrescriptionCFEntry] = []

    var body: some View {
        NavigationStack {
            CabinetView()
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
            do {
                globalCodiceFiscaleEntries = try appDataStore.provider.settings.prescriptionCodiceFiscaleEntriesForLowStock()
            } catch {
                globalCodiceFiscaleEntries = []
            }
            isGlobalCodiceFiscalePresented = true
            appRouter.markRouteHandled(route)
        case .pharmacy:
            appRouter.markRouteHandled(route)
        case .scan, .addMedicine:
            break
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppViewModel())
        .environmentObject(AppRouter())
        .environmentObject(
            AppDataStore(
                provider: CoreDataAppDataProvider(
                    authGateway: SupabaseAuthGatewayAdapter(),
                    backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
                )
            )
        )
}
