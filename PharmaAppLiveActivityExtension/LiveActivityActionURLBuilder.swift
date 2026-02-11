import Foundation

enum LiveActivityActionURLBuilder {
    enum Action: String {
        case markTaken = "mark-taken"
        case remindLater = "remind-later"
    }

    static func makeURL(
        action: Action,
        therapyId: String,
        medicineId: String,
        medicineName: String,
        doseText: String,
        scheduledAt: Date
    ) -> URL {
        var components = URLComponents()
        components.scheme = "pharmaapp"
        components.host = "live-activity"
        components.queryItems = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "therapyId", value: therapyId),
            URLQueryItem(name: "medicineId", value: medicineId),
            URLQueryItem(name: "medicineName", value: medicineName),
            URLQueryItem(name: "doseText", value: doseText),
            URLQueryItem(name: "scheduledAt", value: dateFormatter.string(from: scheduledAt))
        ]
        return components.url ?? URL(string: "pharmaapp://today")!
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
