import SwiftUI
import AuthenticationServices

#if canImport(GoogleSignInSwift)
import GoogleSignInSwift
#endif

struct LoginView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var showError: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.93, green: 0.96, blue: 1.0), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)

                    Text("PharmaApp")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)

                    Text("Accedi per sincronizzare i tuoi dati e mantenere le terapie aggiornate.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 20)

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn, onRequest: auth.handleAppleRequest, onCompletion: auth.handleAppleCompletion)
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    #if canImport(GoogleSignInSwift)
                    GoogleSignInButton(action: auth.signInWithGoogle)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    #else
                    Button {
                        auth.signInWithGoogle()
                    } label: {
                        HStack {
                            Image(systemName: "g.circle.fill")
                            Text("Accedi con Google")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                    }
                    #endif

                    if auth.isBusy {
                        ProgressView()
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)

                Text("Continuando accetti i Termini di utilizzo e la Privacy Policy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .onChange(of: auth.errorMessage) { newValue in
            showError = newValue != nil
        }
        .alert("Errore di accesso", isPresented: $showError) {
            Button("OK", role: .cancel) {
                auth.errorMessage = nil
            }
        } message: {
            Text(auth.errorMessage ?? "Si è verificato un errore.")
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
