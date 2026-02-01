import Foundation

public enum PharmaErrorCode: String, Codable {
    case duplicateOperation = "duplicate_operation"
    case saveFailed = "save_failed"
    case invalidInput = "invalid_input"
    case notFound = "not_found"
}

public struct PharmaError: Error, Equatable {
    public let code: PharmaErrorCode
    public let message: String?

    public init(code: PharmaErrorCode, message: String? = nil) {
        self.code = code
        self.message = message
    }
}
