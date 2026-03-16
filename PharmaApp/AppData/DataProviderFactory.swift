import Foundation
import Supabase

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
            return CoreDataAppDataProvider(
                authGateway: SupabaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: backupCoordinator)
            )
        case .supabase:
            return SupabaseAppDataProvider()
        case .fastapi:
            return makeFastAPIProvider()
        }
    }

    private static func makeFastAPIProvider() -> FastAPIAppDataProvider {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main

        // Resolve FastAPI base URL
        let rawBaseURL = processInfo.environment["FASTAPI_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "FASTAPI_BASE_URL") as? String
            ?? "http://localhost:8000"
        let baseURL = URL(string: rawBaseURL)!

        // Resolve Supabase client (shared with auth)
        let supabaseURL = processInfo.environment["SUPABASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
            ?? ""
        let supabaseKey = processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
            ?? ""

        let supabaseClient = SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey
        )

        let client = FastAPIClient(baseURL: baseURL, supabaseClient: supabaseClient)
        return FastAPIAppDataProvider(client: client)
    }
}
