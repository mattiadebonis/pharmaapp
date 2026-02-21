import XCTest
@testable import PharmaApp

final class MonitoringTodoParserTests: XCTestCase {
    func testParseNewDoseMonitoringIDFormat() throws {
        let id = "monitoring|dose|bloodPressure|beforeDose|therapy-key|1000|900"
        let descriptor = try XCTUnwrap(MonitoringTodoDescriptor.parse(id: id))

        XCTAssertEqual(descriptor.sourceKind, .dose)
        XCTAssertEqual(descriptor.kind, .bloodPressure)
        XCTAssertEqual(descriptor.doseRelation, .beforeDose)
        XCTAssertEqual(descriptor.therapyExternalKey, "therapy-key")
        XCTAssertEqual(descriptor.doseTimestamp?.timeIntervalSince1970, 1000)
        XCTAssertEqual(descriptor.triggerTimestamp.timeIntervalSince1970, 900)
    }

    func testParseLegacyDoseMonitoringIDFormat() throws {
        let id = "monitoring|dose|bloodGlucose|therapy-key|1000"
        let descriptor = try XCTUnwrap(MonitoringTodoDescriptor.parse(id: id))

        XCTAssertEqual(descriptor.sourceKind, .dose)
        XCTAssertEqual(descriptor.kind, .bloodGlucose)
        XCTAssertEqual(descriptor.doseRelation, .beforeDose)
        XCTAssertEqual(descriptor.doseTimestamp?.timeIntervalSince1970, 1000)
        XCTAssertEqual(descriptor.triggerTimestamp.timeIntervalSince1970, 1000)
    }
}
