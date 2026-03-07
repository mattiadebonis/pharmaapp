import Foundation

@MainActor
enum DataProviderFactory {
    static func make(
        config: BackendConfig = BackendConfig(),
        backupCoordinator: BackupCoordinator = BackupCoordinator(
            persistenceController: PersistenceController.shared
        )
    ) -> any AppDataProvider {
        switch config.backend {
        case .coredata:
            FirebaseRuntimeConfigurator.configureIfNeeded()
            return CoreDataAppDataProvider(
                authGateway: FirebaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: backupCoordinator)
            )
        case .supabase:
            return SupabaseAppDataProvider()
        }
    }
}
