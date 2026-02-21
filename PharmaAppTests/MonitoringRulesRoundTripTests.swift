import XCTest
@testable import PharmaApp

final class MonitoringRulesRoundTripTests: XCTestCase {
    func testMonitoringActionRoundTripWithAfterDoseAndFreeMinutesOffset() throws {
        let rules = ClinicalRules(
            monitoring: [
                MonitoringAction(
                    kind: .temperature,
                    doseRelation: .afterDose,
                    offsetMinutes: 45,
                    requiredBeforeDose: false,
                    schedule: nil,
                    leadMinutes: 45
                )
            ]
        )

        let encoded = try XCTUnwrap(rules.encoded())
        let decoded = try XCTUnwrap(ClinicalRules.decode(from: encoded))
        let action = try XCTUnwrap(decoded.monitoring?.first)

        XCTAssertEqual(action.kind, .temperature)
        XCTAssertEqual(action.doseRelation, .afterDose)
        XCTAssertEqual(action.offsetMinutes, 45)
        XCTAssertEqual(action.requiredBeforeDose, false)
        XCTAssertEqual(action.leadMinutes, 45)
        XCTAssertEqual(action.resolvedDoseRelation, .afterDose)
        XCTAssertEqual(action.resolvedOffsetMinutes, 45)
    }
}
