import SwiftUI

struct AuthenticationGateView: View {
    @EnvironmentObject private var auth: AuthViewModel
    // Temporary local bypass while Firebase/Apple auth configuration is being completed.
    private let bypassAuthentication = false

    @StateObject private var migrationCoordinator = MigrationCoordinator()

    var body: some View {
        Group {
            if bypassAuthentication {
                ContentView()
            } else {
                switch auth.state {
                case .loading:
                    ProgressView("Caricamento...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground))
                case .unauthenticated:
                    LoginView()
                case .authenticated:
                    if migrationCoordinator.isMigrationNeeded
                        && migrationCoordinator.state != .completed {
                        MigrationView()
                    } else {
                        ContentView()
                    }
                }
            }
        }
        .task {
            guard !bypassAuthentication else { return }
            auth.start()
        }
    }
}

#Preview {
    AuthenticationGateView()
        .environmentObject(AuthViewModel())
}
