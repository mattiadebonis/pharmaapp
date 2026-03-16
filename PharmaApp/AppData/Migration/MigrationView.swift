import SwiftUI
import Supabase

// MARK: - MigrationView

/// Full-screen view shown during the one-time migration from CoreData to FastAPI.
/// Displays progress, handles errors, and allows retry.
struct MigrationView: View {
    @StateObject private var coordinator = MigrationCoordinator()
    @State private var didStart = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Aggiornamento in corso")
                .font(.title2.bold())

            switch coordinator.state {
            case .idle, .checking, .ready:
                Text("Stiamo aggiornando l'app per sincronizzare i tuoi dati con il server. Questa operazione viene eseguita una sola volta.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                ProgressView()
                    .controlSize(.large)

            case .migrating:
                Text("Sincronizzazione dei dati in corso...\nNon chiudere l'app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                ProgressView()
                    .controlSize(.large)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Migrazione completata!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                if let error = coordinator.errorMessage {
                    Text("Errore: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    coordinator.resetForRetry()
                    didStart = false
                } label: {
                    Label("Riprova", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 48)

            case .notNeeded:
                EmptyView()
            }

            Spacer()
        }
        .task {
            guard !didStart else { return }
            didStart = true
            await startMigration()
        }
    }

    private func startMigration() async {
        let client = makeFastAPIClient()
        await coordinator.performMigration(client: client)
    }

    /// Creates a FastAPIClient for migration using the same config resolution as DataProviderFactory.
    private func makeFastAPIClient() -> FastAPIClient {
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main

        let rawBaseURL = processInfo.environment["FASTAPI_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "FASTAPI_BASE_URL") as? String
            ?? "http://localhost:8000"
        let baseURL = URL(string: rawBaseURL)!

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

        return FastAPIClient(baseURL: baseURL, supabaseClient: supabaseClient)
    }
}
