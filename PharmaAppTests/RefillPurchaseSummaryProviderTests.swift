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

    @MainActor
    @Test func summaryIncludesOnlyMedicinesUnderThreshold() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext

        let lowMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        lowMedicine.nome = "Tachipirina"
        let lowPackage = try TestCoreDataFactory.makePackage(context: context, medicine: lowMedicine)

        let okMedicine = try TestCoreDataFactory.makeMedicine(context: context)
        okMedicine.nome = "Aspirina"
        let okPackage = try TestCoreDataFactory.makePackage(context: context, medicine: okMedicine)

        let stockService = StockService(context: context)
        stockService.setUnits(2, for: lowPackage)
        stockService.setUnits(20, for: okPackage)

        try context.save()

        let provider = RefillPurchaseSummaryProvider(context: context)
        let summary = provider.summary(maxVisible: 5, strategy: .lightweightTodos)

        #expect(summary.allNames == ["Tachipirina"])
        #expect(summary.hasItems)
    }
}
