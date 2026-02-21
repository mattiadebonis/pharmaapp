import XCTest
@testable import PharmaApp

final class ClinicalRulesMonitoringCompatibilityTests: XCTestCase {
    func testLegacyMonitoringPayloadFallsBackToBeforeDoseAndLeadMinutes() throws {
        let json = """
        {
          "monitoring": [
            {
              "kind": "bloodPressure",
              "requiredBeforeDose": true,
              "leadMinutes": 45
            }
          ]
        }
        """

        let rules = ClinicalRules.decode(from: Data(json.utf8))
        let action = try XCTUnwrap(rules?.monitoring?.first)

        XCTAssertNil(action.doseRelation)
        XCTAssertNil(action.offsetMinutes)
        XCTAssertEqual(action.resolvedDoseRelation, .beforeDose)
        XCTAssertEqual(action.resolvedOffsetMinutes, 45)
    }

    func testNewMonitoringPayloadKeepsDoseRelationAndOffsetMinutes() throws {
        let rules = ClinicalRules(
            monitoring: [
                MonitoringAction(
                    kind: .heartRate,
                    doseRelation: .afterDose,
                    offsetMinutes: 60,
                    requiredBeforeDose: false,
                    schedule: nil,
                    leadMinutes: 60
                )
            ]
        )

        let data = try XCTUnwrap(rules.encoded())
        let decoded = try XCTUnwrap(ClinicalRules.decode(from: data))
        let action = try XCTUnwrap(decoded.monitoring?.first)

        XCTAssertEqual(action.kind, .heartRate)
        XCTAssertEqual(action.doseRelation, .afterDose)
        XCTAssertEqual(action.offsetMinutes, 60)
        XCTAssertEqual(action.resolvedDoseRelation, .afterDose)
        XCTAssertEqual(action.resolvedOffsetMinutes, 60)
    }
}
