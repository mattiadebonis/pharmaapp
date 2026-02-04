import Testing
@testable import PharmaApp

struct CodiceFiscaleValidatorTests {
    @Test func normalizeTrimsAndUppercases() async throws {
        #expect(CodiceFiscaleValidator.normalize("  abcd1234efgh5678 \n") == "ABCD1234EFGH5678")
    }

    @Test func validationRejectsInvalid() async throws {
        #expect(!CodiceFiscaleValidator.isValid("ABC"))
        #expect(!CodiceFiscaleValidator.isValid("ABCD1234EFGH567!"))
        #expect(!CodiceFiscaleValidator.isValid("ABCD1234EFGH56789"))
    }

    @Test func validationAcceptsValid() async throws {
        #expect(CodiceFiscaleValidator.isValid("ABCD1234EFGH5678"))
    }
}
