import Foundation

struct RefillCooldownConfiguration: Equatable {
    let globalCooldown: TimeInterval
    let samePharmacyCooldown: TimeInterval

    static let `default` = RefillCooldownConfiguration(
        globalCooldown: 8 * 60 * 60,
        samePharmacyCooldown: 24 * 60 * 60
    )
}

protocol RefillActivityStateStoring {
    func canShow(for pharmacyId: String, now: Date) -> Bool
    func markShown(for pharmacyId: String, activityId: String, startedAt: Date, now: Date)
    func activeActivityId() -> String?
    func activePharmacyId() -> String?
    func activeStartedAt() -> Date?
    func setActive(activityId: String, pharmacyId: String, startedAt: Date)
    func clearActive()
}

final class UserDefaultsRefillActivityStateStore: RefillActivityStateStoring {
    private enum Keys {
        static let lastGlobalShownAt = "refill.liveactivity.lastGlobalShownAt"
        static let lastShownByPharmacy = "refill.liveactivity.lastShownByPharmacy"
        static let activeActivityId = "refill.liveactivity.activeActivityId"
        static let activePharmacyId = "refill.liveactivity.activePharmacyId"
        static let activeStartedAt = "refill.liveactivity.activeStartedAt"
    }

    private let defaults: UserDefaults
    private let config: RefillCooldownConfiguration

    init(
        defaults: UserDefaults = .standard,
        config: RefillCooldownConfiguration = .default
    ) {
        self.defaults = defaults
        self.config = config
    }

    func canShow(for pharmacyId: String, now: Date = Date()) -> Bool {
        if let lastGlobal = defaults.object(forKey: Keys.lastGlobalShownAt) as? Date {
            let globalDelta = now.timeIntervalSince(lastGlobal)
            if globalDelta < config.globalCooldown {
                return false
            }
        }

        let byPharmacy = loadLastShownByPharmacy()
        if let lastForPharmacy = byPharmacy[pharmacyId] {
            let pharmacyDelta = now.timeIntervalSince(lastForPharmacy)
            if pharmacyDelta < config.samePharmacyCooldown {
                return false
            }
        }

        return true
    }

    func markShown(for pharmacyId: String, activityId: String, startedAt: Date, now: Date = Date()) {
        defaults.set(now, forKey: Keys.lastGlobalShownAt)

        var byPharmacy = loadLastShownByPharmacy()
        byPharmacy[pharmacyId] = now
        saveLastShownByPharmacy(byPharmacy)

        setActive(activityId: activityId, pharmacyId: pharmacyId, startedAt: startedAt)
    }

    func activeActivityId() -> String? {
        defaults.string(forKey: Keys.activeActivityId)
    }

    func activePharmacyId() -> String? {
        defaults.string(forKey: Keys.activePharmacyId)
    }

    func activeStartedAt() -> Date? {
        defaults.object(forKey: Keys.activeStartedAt) as? Date
    }

    func setActive(activityId: String, pharmacyId: String, startedAt: Date) {
        defaults.set(activityId, forKey: Keys.activeActivityId)
        defaults.set(pharmacyId, forKey: Keys.activePharmacyId)
        defaults.set(startedAt, forKey: Keys.activeStartedAt)
    }

    func clearActive() {
        defaults.removeObject(forKey: Keys.activeActivityId)
        defaults.removeObject(forKey: Keys.activePharmacyId)
        defaults.removeObject(forKey: Keys.activeStartedAt)
    }

    private func loadLastShownByPharmacy() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: Keys.lastShownByPharmacy) as? [String: TimeInterval] else {
            return [:]
        }
        return raw.reduce(into: [String: Date]()) { partialResult, pair in
            partialResult[pair.key] = Date(timeIntervalSince1970: pair.value)
        }
    }

    private func saveLastShownByPharmacy(_ value: [String: Date]) {
        let raw = value.reduce(into: [String: TimeInterval]()) { partialResult, pair in
            partialResult[pair.key] = pair.value.timeIntervalSince1970
        }
        defaults.set(raw, forKey: Keys.lastShownByPharmacy)
    }
}
