import Foundation
import AuthenticationServices
import Supabase

@MainActor
final class SupabaseAuthGatewayAdapter: AuthGateway {
    private let bundle: Bundle
    private let processInfo: ProcessInfo

    private static var cachedClient: SupabaseClient?
    private static var cachedConfig: SupabaseAuthConfiguration?

    init(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.bundle = bundle
        self.processInfo = processInfo
    }

    var currentUser: AuthUser? {
        guard let client = try? resolveClient() else { return nil }
        return Self.mapUser(client.auth.currentUser)
    }

    func observeAuthState() -> AsyncStream<AuthUser?> {
        AsyncStream { continuation in
            guard let client = try? resolveClient() else {
                continuation.yield(nil)
                continuation.finish()
                return
            }

            continuation.yield(Self.mapUser(client.auth.currentUser))

            let task = Task {
                for await (_, session) in client.auth.authStateChanges {
                    if Task.isCancelled {
                        break
                    }
                    continuation.yield(Self.mapUser(session?.user))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        let client = try resolveClient()
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
    }

    func signInWithApple(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let client = try resolveClient()
        _ = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        if let fullName {
            let formatter = PersonNameComponentsFormatter()
            let displayName = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
            if !displayName.isEmpty {
                try await updateCurrentUser(displayName: displayName, photoURL: nil)
            }
        }
    }

    func signOut() throws {
        guard let client = try? resolveClient() else { return }
        Task {
            try? await client.auth.signOut()
        }
    }

    func updateCurrentUser(displayName: String?, photoURL: URL?) async throws {
        let client = try resolveClient()

        let normalizedName = Self.sanitizedValue(displayName)
        let normalizedPhotoURL = Self.sanitizedValue(photoURL?.absoluteString)

        guard normalizedName != nil || normalizedPhotoURL != nil else { return }

        var metadata: [String: AnyJSON] = [:]
        if let normalizedName {
            metadata["full_name"] = .string(normalizedName)
            metadata["name"] = .string(normalizedName)
        }
        if let normalizedPhotoURL {
            metadata["avatar_url"] = .string(normalizedPhotoURL)
            metadata["picture"] = .string(normalizedPhotoURL)
        }

        _ = try await client.auth.update(
            user: UserAttributes(data: metadata)
        )
    }

    func isConfigured() -> Bool {
        Self.loadConfiguration(bundle: bundle, processInfo: processInfo) != nil
    }

    func googleClientID() -> String? {
        Self.sanitizedValue(
            processInfo.environment["GOOGLE_CLIENT_ID"]
                ?? bundle.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String
                ?? bundle.object(forInfoDictionaryKey: "GIDClientID") as? String
        )
    }

    private func resolveClient() throws -> SupabaseClient {
        guard let configuration = Self.loadConfiguration(bundle: bundle, processInfo: processInfo) else {
            throw AuthGatewayError.message(
                "Configurazione Supabase mancante. Imposta SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY."
            )
        }

        if let cachedClient = Self.cachedClient,
           let cachedConfig = Self.cachedConfig,
           cachedConfig == configuration {
            return cachedClient
        }

        let client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey
        )
        Self.cachedConfig = configuration
        Self.cachedClient = client
        return client
    }

    private static func loadConfiguration(
        bundle: Bundle,
        processInfo: ProcessInfo
    ) -> SupabaseAuthConfiguration? {
        let rawURL = sanitizedValue(
            processInfo.environment["SUPABASE_URL"]
                ?? bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        )
        let rawKey = sanitizedValue(
            processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]
                ?? bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
        )

        guard let rawURL,
              let url = URL(string: rawURL),
              let rawKey else {
            return nil
        }

        return SupabaseAuthConfiguration(url: url, publishableKey: rawKey)
    }

    private static func mapUser(_ user: User?) -> AuthUser? {
        guard let user else { return nil }

        let provider: AuthProvider
        if let identityProvider = user.identities?
            .map({ $0.provider.lowercased() })
            .first(where: { $0 == AuthProvider.apple.rawValue || $0 == AuthProvider.google.rawValue }) {
            provider = AuthProvider(rawValue: identityProvider) ?? .google
        } else if let providerFromMetadata = user.appMetadata["provider"]?.stringValue?.lowercased(),
                  let parsedProvider = AuthProvider(rawValue: providerFromMetadata) {
            provider = parsedProvider
        } else {
            provider = .google
        }

        let fullName = sanitizedValue(
            user.userMetadata["full_name"]?.stringValue
                ?? user.userMetadata["name"]?.stringValue
        )

        let imageURL = sanitizedValue(
            user.userMetadata["avatar_url"]?.stringValue
                ?? user.userMetadata["picture"]?.stringValue
        ).flatMap(URL.init(string:))

        return AuthUser(
            id: user.id.uuidString,
            provider: provider,
            email: sanitizedValue(user.email),
            fullName: fullName,
            imageURL: imageURL
        )
    }

    private static func sanitizedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("$("), trimmed.hasSuffix(")") {
            return nil
        }
        if trimmed.uppercased().contains("REPLACE_WITH_") {
            return nil
        }
        return trimmed
    }
}

private struct SupabaseAuthConfiguration: Equatable {
    let url: URL
    let publishableKey: String
}
