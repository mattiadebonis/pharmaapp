import Foundation

enum CabinetSummarySharedStore {
    static let suiteName = "group.pharmapp-1987"
    private static let linesKey = "cabinetSummaryLines"
    private static let inlineActionKey = "cabinetSummaryInlineAction"

    static func write(_ lines: [String], inlineAction: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(lines, forKey: linesKey)
        defaults.set(inlineAction, forKey: inlineActionKey)
    }

    static func read() -> [String] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        return defaults.stringArray(forKey: linesKey) ?? []
    }

    static func readInlineAction() -> String {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return "" }
        return defaults.string(forKey: inlineActionKey) ?? ""
    }
}
