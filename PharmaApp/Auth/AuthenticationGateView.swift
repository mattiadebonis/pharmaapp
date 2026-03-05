import SwiftUI

struct AuthenticationGateView: View {
    @EnvironmentObject private var auth: AuthViewModel
    // Temporary local bypass while Firebase/Apple auth configuration is being completed.
    private let bypassAuthentication = true

    var body: some View {
        Group {
            if bypassAuthentication {
                ContentView()
            } else {
                switch auth.state {
                case .loading:
                    ProgressView("Caricamento...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                case .unauthenticated:
                    LoginView()
                case .authenticated:
                    ContentView()
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
