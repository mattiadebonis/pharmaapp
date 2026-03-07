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

    private let userDefaults: UserDefaults
    private var authUserIDProvider: () -> String?
    private let userIdKey: String
    private let deviceIdKey: String

    init(
        userDefaults: UserDefaults = .standard,
        userIdKey: String = "pharmaapp.user_id",
        deviceIdKey: String = "pharmaapp.device_id",
        authUserIDProvider: @escaping () -> String? = { nil }
    ) {
        self.userDefaults = userDefaults
        self.userIdKey = userIdKey
        self.deviceIdKey = deviceIdKey
        self.authUserIDProvider = authUserIDProvider
    }

    func configureAuthUserIDProvider(_ provider: @escaping () -> String?) {
        authUserIDProvider = provider
    }

    var userId: String {
        if let authenticatedUserID = normalizedValue(from: authUserIDProvider()) {
            return authenticatedUserID
        }
        return legacyUserId
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
    func ensureProfile(in context: NSManagedObjectContext, authUser: AuthUser? = nil) {
        let effectiveUserId = authUser?.id ?? userId
        let request = UserProfile.fetchRequest(for: effectiveUserId)
        let profile = (try? context.fetch(request).first) ?? UserProfile(context: context)

        if profile.value(forKey: "id") == nil {
            profile.id = UUID()
        }
        if profile.user_id == nil || profile.user_id?.isEmpty == true {
            profile.user_id = effectiveUserId
        }
        if profile.user_id != effectiveUserId {
            profile.user_id = effectiveUserId
        }
        if profile.device_id == nil || profile.device_id?.isEmpty == true {
            profile.device_id = deviceId
        }
        if let displayName = normalizedValue(from: authUser?.displayName) {
            profile.display_name = displayName
        }
        if profile.created_at == nil {
            profile.created_at = Date()
        }

        saveIfNeeded(context)
    }

    @MainActor
    func syncAuthenticatedIdentity(from authUser: AuthUser?, in context: NSManagedObjectContext) {
        guard let authUser else {
            return
        }
        let legacyUserId = self.legacyUserId
        userDefaults.set(authUser.id, forKey: userIdKey)
        migrateUserProfile(from: legacyUserId, to: authUser, in: context)
        migrateNotificationSettings(from: legacyUserId, to: authUser.id, in: context)
        migrateCabinetMemberships(from: legacyUserId, to: authUser.id, in: context)
        ensureProfile(in: context, authUser: authUser)
    }

    private var legacyUserId: String {
        if let existing = userDefaults.string(forKey: userIdKey) {
            return existing
        }
        let newId = UUID().uuidString
        userDefaults.set(newId, forKey: userIdKey)
        return newId
    }

    @MainActor
    private func migrateUserProfile(from legacyUserId: String, to authUser: AuthUser, in context: NSManagedObjectContext) {
        let legacyRequest = UserProfile.fetchRequest(for: legacyUserId)
        let authenticatedRequest = UserProfile.fetchRequest(for: authUser.id)

        let legacyProfile = try? context.fetch(legacyRequest).first
        let authenticatedProfile = try? context.fetch(authenticatedRequest).first
        let targetProfile = authenticatedProfile ?? legacyProfile ?? UserProfile(context: context)

        if targetProfile.value(forKey: "id") == nil {
            targetProfile.id = UUID()
        }
        targetProfile.user_id = authUser.id
        if targetProfile.created_at == nil {
            targetProfile.created_at = legacyProfile?.created_at ?? Date()
        }
        if normalizedValue(from: targetProfile.device_id) == nil {
            targetProfile.device_id = normalizedValue(from: legacyProfile?.device_id) ?? deviceId
        }
        if normalizedValue(from: targetProfile.display_name) == nil {
            targetProfile.display_name = normalizedValue(from: authUser.displayName) ?? normalizedValue(from: legacyProfile?.display_name)
        } else if let authDisplayName = normalizedValue(from: authUser.displayName) {
            targetProfile.display_name = authDisplayName
        }

        if let legacyProfile,
           let authenticatedProfile,
           legacyProfile.objectID != authenticatedProfile.objectID {
            context.delete(legacyProfile)
        }

        saveIfNeeded(context)
    }

    @MainActor
    private func migrateNotificationSettings(from legacyUserId: String, to authenticatedUserId: String, in context: NSManagedObjectContext) {
        let legacyRequest = NotificationSettings.fetchRequest(for: legacyUserId)
        let currentRequest = NotificationSettings.fetchRequest(for: authenticatedUserId)

        let legacySettings = try? context.fetch(legacyRequest).first
        let currentSettings = try? context.fetch(currentRequest).first

        guard let legacySettings else { return }

        if let currentSettings, currentSettings.objectID != legacySettings.objectID {
            let legacyUpdatedAt = legacySettings.updated_at ?? .distantPast
            let currentUpdatedAt = currentSettings.updated_at ?? .distantPast
            if legacyUpdatedAt > currentUpdatedAt {
                currentSettings.grace_minutes = legacySettings.grace_minutes
                currentSettings.notify_caregivers = legacySettings.notify_caregivers
                currentSettings.notify_shared = legacySettings.notify_shared
                currentSettings.updated_at = legacySettings.updated_at
            }
            context.delete(legacySettings)
        } else {
            legacySettings.user_id = authenticatedUserId
        }

        saveIfNeeded(context)
    }

    @MainActor
    private func migrateCabinetMemberships(from legacyUserId: String, to authenticatedUserId: String, in context: NSManagedObjectContext) {
        let request = CabinetMembership.fetchRequest() as! NSFetchRequest<CabinetMembership>
        request.predicate = NSPredicate(format: "user_id == %@", legacyUserId)
        let legacyMemberships = (try? context.fetch(request)) ?? []
        guard !legacyMemberships.isEmpty else { return }

        for membership in legacyMemberships {
            guard let cabinet = membership.cabinet else {
                membership.user_id = authenticatedUserId
                continue
            }

            let currentRequest = CabinetMembership.fetchRequest(for: cabinet)
            let currentMembership = try? context.fetch(currentRequest)
                .first(where: { $0.user_id == authenticatedUserId })

            if let currentMembership, currentMembership.objectID != membership.objectID {
                if currentMembership.created_at == nil {
                    currentMembership.created_at = membership.created_at
                }
                context.delete(membership)
            } else {
                membership.user_id = authenticatedUserId
            }
        }

        saveIfNeeded(context)
    }

    private func normalizedValue(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func saveIfNeeded(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
