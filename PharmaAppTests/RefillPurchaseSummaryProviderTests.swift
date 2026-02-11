import Foundation
import Testing
@testable import PharmaApp

struct RefillPurchaseSummaryProviderTests {
    @MainActor
    @Test func deduplicatePreservesOrderAndRemovesEmpty() {
        let input = [
            " Tachipirina ",
            "", 
            "Moment",
            "tachipirina",
            "   ",
            "Aspirina"
        ]

        let output = RefillPurchaseSummaryProvider.deduplicatedTitles(input)
        #expect(output == ["Tachipirina", "Moment", "Aspirina"])
    }
}
