import Foundation
import SwiftUI

enum CodiceFiscaleStoreError: LocalizedError {
    case invalidFormat
    case keychainFailure(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Il Codice Fiscale deve avere 16 caratteri alfanumerici."
        case .keychainFailure:
            return "Impossibile salvare il Codice Fiscale."
        }
    }
}

@MainActor
final class CodiceFiscaleStore: ObservableObject {
    @Published private(set) var codiceFiscale: String?
    private let keychain: KeychainClient

    init(keychain: KeychainClient = KeychainClient()) {
        self.keychain = keychain
        load()
    }

    func load() {
        do {
            codiceFiscale = try keychain.read()
        } catch {
            codiceFiscale = nil
            print("⚠️ CodiceFiscaleStore.load: \(error)")
        }
    }

    func save(from input: String) throws {
        let normalized = CodiceFiscaleValidator.normalize(input)
        guard CodiceFiscaleValidator.isValid(normalized) else {
            throw CodiceFiscaleStoreError.invalidFormat
        }
        do {
            try keychain.save(normalized)
            codiceFiscale = normalized
        } catch {
            throw CodiceFiscaleStoreError.keychainFailure(error)
        }
    }

    func clear() throws {
        do {
            try keychain.delete()
            codiceFiscale = nil
        } catch {
            throw CodiceFiscaleStoreError.keychainFailure(error)
        }
    }
}
