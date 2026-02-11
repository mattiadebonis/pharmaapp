//
//  UserIdentityProvider.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import Foundation
import CoreData
import UIKit

final class UserIdentityProvider {
    static let shared = UserIdentityProvider()

    private let userDefaults = UserDefaults.standard
    private let userIdKey = "pharmaapp.user_id"
    private let deviceIdKey = "pharmaapp.device_id"

    private init() {}

    var userId: String {
        if let existing = userDefaults.string(forKey: userIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        userDefaults.set(newId, forKey: userIdKey)
        return newId
    }

    var deviceId: String {
        if let existing = userDefaults.string(forKey: deviceIdKey) {
            return existing
        }
        let identifier = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        userDefaults.set(identifier, forKey: deviceIdKey)
        return identifier
    }

    @MainActor
    func ensureProfile(in context: NSManagedObjectContext) {
        let userId = self.userId
        let request = UserProfile.fetchRequest(for: userId)
        if let existing = try? context.fetch(request).first {
            if existing.device_id == nil || existing.device_id?.isEmpty == true {
                existing.device_id = deviceId
            }
            return
        }

        let profile = UserProfile(context: context)
        profile.id = UUID()
        profile.user_id = userId
        profile.device_id = deviceId
        profile.created_at = Date()
        try? context.save()
    }
}
