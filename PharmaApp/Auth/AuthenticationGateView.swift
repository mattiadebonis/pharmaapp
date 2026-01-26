import SwiftUI

struct AuthenticationGateView: View {
    @EnvironmentObject private var auth: AuthViewModel

    var body: some View {
        Group {
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
}

#Preview {
    AuthenticationGateView()
        .environmentObject(AuthViewModel())
}
