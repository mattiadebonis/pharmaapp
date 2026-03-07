import Foundation

enum DataScope: String, CaseIterable, Hashable {
    case medicines
    case therapies
    case logs
    case stocks
    case cabinets
    case people
    case doctors
    case options
    case notifications
    case auth
    case backup
}

struct DataChangeEvent: Equatable {
    let scope: DataScope
    let reason: String
    let at: Date
}

enum BackendType: String, CaseIterable {
    case coredata
    case supabase
}

struct BackendConfig {
    private static let launchArgumentKey = "-data-backend"
    private static let environmentKey = "PHARMAAPP_DATA_BACKEND"
    private static let userDefaultsKey = "pharmaapp.data_backend"

    let backend: BackendType

    init(
        processInfo: ProcessInfo = .processInfo,
        userDefaults: UserDefaults = .standard
    ) {
        if let launchBackend = Self.backendFromLaunchArguments(processInfo.arguments) {
            backend = launchBackend
            return
        }

        if let environmentBackend = Self.backend(from: processInfo.environment[Self.environmentKey]) {
            backend = environmentBackend
            return
        }

        if let defaultsBackend = Self.backend(from: userDefaults.string(forKey: Self.userDefaultsKey)) {
            backend = defaultsBackend
            return
        }

        backend = .coredata
    }

    private static func backendFromLaunchArguments(_ arguments: [String]) -> BackendType? {
        guard let index = arguments.firstIndex(of: launchArgumentKey), arguments.indices.contains(index + 1) else {
            return nil
        }
        return backend(from: arguments[index + 1])
    }

    private static func backend(from rawValue: String?) -> BackendType? {
        guard let rawValue else { return nil }
        return BackendType(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}
