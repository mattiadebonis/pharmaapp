import Foundation
import AppIntents

enum SiriIntentSupport {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeStyle = .short
        return formatter
    }()

    static func dialog(_ text: String) -> IntentDialog {
        IntentDialog(stringLiteral: text)
    }

    static func joinedList(_ values: [String]) -> String {
        if values.isEmpty { return "" }
        if values.count == 1 { return values[0] }
        if values.count == 2 { return "\(values[0]) e \(values[1])" }
        let prefix = values.dropLast().joined(separator: ", ")
        return "\(prefix) e \(values.last!)"
    }
}
