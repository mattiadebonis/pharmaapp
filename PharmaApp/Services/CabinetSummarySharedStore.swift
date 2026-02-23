import Foundation

enum CabinetSummarySharedStore {
    static let suiteName = "group.pharmapp-1987"
    private static let key = "cabinetSummaryLines"

    static func write(_ lines: [String]) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(lines, forKey: key)
    }

    static func read() -> [String] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [] }
        return defaults.stringArray(forKey: key) ?? []
    }
}
