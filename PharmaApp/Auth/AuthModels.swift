import Foundation

enum AuthProvider: String, Codable {
    case apple
    case google
}

struct AuthUser: Codable, Equatable {
    let id: String
    let provider: AuthProvider
    var email: String?
    var fullName: String?
    var imageURL: URL?

    var displayName: String {
        if let fullName, !fullName.isEmpty {
            return fullName
        }
        if let email, !email.isEmpty {
            return email
        }
        return id
    }
}
