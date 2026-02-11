import Foundation
import Testing
@testable import PharmaApp

struct NotificationSchedulerDescriptorTests {
    @Test func alarmModeExpandsTherapyIntoSevenNotifications() {
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let medicineId = UUID().uuidString
        let item = makeTherapyItem(
            id: "therapy-base",
            date: now.addingTimeInterval(300),
            medicineId: medicineId
        )
        let preferences = TherapyNotificationPreferences(levelRawValue: "alarm", snoozeMinutesRawValue: 10)

        let descriptors = NotificationScheduler.buildRequestDescriptors(
            items: [item],
            preferences: preferences,
            now: now,
            pendingCap: 60
        )

        #expect(descriptors.count == 7)
        #expect(descriptors.allSatisfy { $0.categoryIdentifier == TherapyAlarmNotificationConstants.categoryIdentifier })
        #expect(descriptors.allSatisfy { $0.interruptionLevel == .timeSensitive })
        #expect(descriptors.allSatisfy { $0.userInfo["medicineId"] == medicineId })

        let seriesIds = Set(descriptors.compactMap { $0.userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] })
        #expect(seriesIds.count == 1)

        for index in 1..<descriptors.count {
            let delta = descriptors[index].date.timeIntervalSince(descriptors[index - 1].date)
            #expect(Int(delta) == 60)
        }
    }

    @Test func pendingCapKeepsNearestRequestsFirst() {
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let firstMedicine = UUID().uuidString
        let secondMedicine = UUID().uuidString

        let stock = NotificationPlanItem(
            id: "stock-immediate",
            date: now,
            title: "Stock",
            body: "stock",
            kind: .stockLow,
            origin: .immediate,
            userInfo: ["type": NotificationPlanKind.stockLow.rawValue, "medicineId": UUID().uuidString]
        )
        let firstTherapy = makeTherapyItem(
            id: "therapy-first",
            date: now.addingTimeInterval(3600),
            medicineId: firstMedicine
        )
        let secondTherapy = makeTherapyItem(
            id: "therapy-second",
            date: now.addingTimeInterval(18_000),
            medicineId: secondMedicine
        )

        let descriptors = NotificationScheduler.buildRequestDescriptors(
            items: [stock, firstTherapy, secondTherapy],
            preferences: TherapyNotificationPreferences(levelRawValue: "alarm", snoozeMinutesRawValue: 10),
            now: now,
            pendingCap: 8
        )

        #expect(descriptors.count == 8)
        #expect(descriptors.first?.identifier == "stock-immediate")
        #expect(!descriptors.contains(where: { $0.userInfo["medicineId"] == secondMedicine }))
    }

    @Test func normalModeKeepsSingleTherapyNotification() {
        let now = Date(timeIntervalSince1970: 1_739_000_000)
        let item = makeTherapyItem(
            id: "therapy-normal",
            date: now.addingTimeInterval(300),
            medicineId: UUID().uuidString
        )

        let descriptors = NotificationScheduler.buildRequestDescriptors(
            items: [item],
            preferences: TherapyNotificationPreferences(levelRawValue: "normal", snoozeMinutesRawValue: 10),
            now: now,
            pendingCap: 60
        )

        #expect(descriptors.count == 1)
        #expect(descriptors[0].identifier == "therapy-normal")
        #expect(descriptors[0].categoryIdentifier == NotificationPlanKind.therapy.rawValue)
        #expect(descriptors[0].userInfo[TherapyAlarmNotificationConstants.alarmSeriesIdKey] == nil)
    }

    private func makeTherapyItem(id: String, date: Date, medicineId: String) -> NotificationPlanItem {
        NotificationPlanItem(
            id: id,
            date: date,
            title: "Therapy",
            body: "body",
            kind: .therapy,
            origin: .scheduled,
            userInfo: [
                "type": NotificationPlanKind.therapy.rawValue,
                "therapyId": "therapy-id",
                "medicineId": medicineId
            ]
        )
    }
}
