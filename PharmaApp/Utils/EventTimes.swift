//
//  EventTimes.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData

enum EventTimeKind: String, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case dinner
    case bedtime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Colazione"
        case .lunch: return "Pranzo"
        case .dinner: return "Cena"
        case .bedtime: return "A letto"
        }
    }

    var defaultHourMinute: (hour: Int, minute: Int) {
        switch self {
        case .breakfast: return (8, 0)
        case .lunch: return (13, 0)
        case .dinner: return (20, 0)
        case .bedtime: return (23, 0)
        }
    }
}

enum EventTimeSettings {
    static func optionTime(_ option: Option?, kind: EventTimeKind) -> Date? {
        guard let option else { return nil }
        switch kind {
        case .breakfast: return option.breakfast_time
        case .lunch: return option.lunch_time
        case .dinner: return option.dinner_time
        case .bedtime: return option.bedtime_time
        }
    }

    static func setOptionTime(_ time: Date, kind: EventTimeKind, option: Option) {
        switch kind {
        case .breakfast: option.breakfast_time = time
        case .lunch: option.lunch_time = time
        case .dinner: option.dinner_time = time
        case .bedtime: option.bedtime_time = time
        }
    }

    static func time(for option: Option?, kind: EventTimeKind, base: Date) -> Date {
        if let stored = optionTime(option, kind: kind) {
            return normalizedTime(from: stored, base: base)
        }
        let defaultTime = defaultTime(for: kind, base: base)
        return defaultTime
    }

    static func defaultTime(for kind: EventTimeKind, base: Date) -> Date {
        let components = kind.defaultHourMinute
        return makeTime(base: base, hour: components.hour, minute: components.minute)
    }

    static func ensureDefaults(option: Option, base: Date) {
        for kind in EventTimeKind.allCases {
            if optionTime(option, kind: kind) == nil {
                let defaultValue = defaultTime(for: kind, base: base)
                setOptionTime(defaultValue, kind: kind, option: option)
            }
        }
    }

    static func normalizedTime(from source: Date, base: Date) -> Date {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: timeComponents.hour ?? 0,
            minute: timeComponents.minute ?? 0,
            second: timeComponents.second ?? 0,
            of: base
        ) ?? base
    }

    private static func makeTime(base: Date, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
}
