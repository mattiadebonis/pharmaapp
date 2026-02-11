import Foundation
import Testing
@testable import PharmaApp

struct RefillPharmacyHoursResolverTests {
    @Test func openInfoReturnsOpenWhenNowIsInsideSlot() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 11
        components.hour = 10
        components.minute = 15
        let now = Calendar(identifier: .gregorian).date(from: components)!

        let info = RefillPharmacyHoursResolver.openInfo(fromSlot: "9:00-13:00 e 15:30-19:30", now: now)

        #expect(info.isOpen)
        #expect(info.closingTimeText == "aperta fino alle 13:00")
    }

    @Test func openInfoReturnsClosedWhenNowIsOutsideSlot() {
        var components = DateComponents()
        components.year = 2026
        components.month = 2
        components.day = 11
        components.hour = 14
        components.minute = 0
        let now = Calendar(identifier: .gregorian).date(from: components)!

        let info = RefillPharmacyHoursResolver.openInfo(fromSlot: "9:00-13:00 e 15:30-19:30", now: now)

        #expect(info.isOpen == false)
        #expect(info.closingTimeText == nil)
    }
}
