import Foundation

enum CodiceFiscaleValidator {
    static func normalize(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isValid(_ input: String) -> Bool {
        let normalized = normalize(input)
        let pattern = "^[A-Z0-9]{16}$"
        return normalized.range(of: pattern, options: .regularExpression) != nil
    }
}
