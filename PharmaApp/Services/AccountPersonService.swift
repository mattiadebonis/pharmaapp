import Foundation
import CoreData

@MainActor
final class AccountPersonService {
    static let shared = AccountPersonService()

    private let keychain: KeychainClient
    private let userDefaults: UserDefaults
    private let migrationFlagKey = "pharmaapp.migration.account_person_cf.v1"

    init(
        keychain: KeychainClient = KeychainClient(),
        userDefaults: UserDefaults = .standard
    ) {
        self.keychain = keychain
        self.userDefaults = userDefaults
    }

    @discardableResult
    func ensureAccountPerson(in context: NSManagedObjectContext) -> Person {
        let request = Person.extractPersons(includeAccount: true)
        request.predicate = NSPredicate(format: "is_account == YES")

        let existing = (try? context.fetch(request)) ?? []
        let account: Person

        if let first = existing.first {
            account = first
        } else {
            let created = Person(context: context)
            created.id = UUID()
            created.nome = "Account"
            created.cognome = nil
            created.is_account = true
            account = created
        }

        if !account.is_account {
            account.is_account = true
        }
        if account.id == nil {
            account.id = UUID()
        }

        // Manteniamo una sola persona account.
        for duplicate in existing.dropFirst() where duplicate.is_account {
            duplicate.is_account = false
        }

        if normalizedName(from: account.nome) == nil {
            account.nome = "Account"
        }

        saveIfNeeded(context)
        return account
    }

    func syncAccountDisplayName(from authUser: AuthUser?, in context: NSManagedObjectContext) {
        let account = ensureAccountPerson(in: context)
        let fallbackName = normalizedName(from: account.nome) ?? "Account"
        let newName = normalizedName(from: authUser?.displayName) ?? fallbackName

        if account.nome != newName {
            account.nome = newName
            saveIfNeeded(context)
        }
    }

    func migrateLegacyCodiceFiscaleIfNeeded(in context: NSManagedObjectContext) {
        if userDefaults.bool(forKey: migrationFlagKey) {
            return
        }

        defer {
            userDefaults.set(true, forKey: migrationFlagKey)
        }

        let account = ensureAccountPerson(in: context)
        if let current = account.codice_fiscale,
           CodiceFiscaleValidator.isValid(CodiceFiscaleValidator.normalize(current)) {
            return
        }

        guard let legacyValue = try? keychain.read(),
              CodiceFiscaleValidator.isValid(CodiceFiscaleValidator.normalize(legacyValue)) else {
            return
        }

        account.codice_fiscale = CodiceFiscaleValidator.normalize(legacyValue)
        saveIfNeeded(context)

        // Dopo la migrazione manteniamo una sola sorgente di verità su Person.
        try? keychain.delete()
    }

    private func normalizedName(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Errore salvataggio AccountPersonService: \(error.localizedDescription)")
        }
    }
}
