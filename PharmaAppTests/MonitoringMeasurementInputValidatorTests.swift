import XCTest
@testable import PharmaApp

final class MonitoringMeasurementInputValidatorTests: XCTestCase {
    func testBloodPressureRequiresTwoIntegerValues() {
        let missingDiastolic = MonitoringMeasurementInputValidator.validate(
            kind: .bloodPressure,
            primary: "120",
            secondary: nil
        )
        if case .success = missingDiastolic {
            XCTFail("Expected validation failure when diastolic is missing")
        }

        let success = MonitoringMeasurementInputValidator.validate(
            kind: .bloodPressure,
            primary: "120",
            secondary: "80"
        )
        guard case let .success(validated) = success else {
            return XCTFail("Expected valid pressure input")
        }
        XCTAssertEqual(validated.primaryValue, 120)
        XCTAssertEqual(validated.secondaryValue, 80)
        XCTAssertEqual(validated.unit, "mmHg")
    }

    func testTemperatureAcceptsDecimalValues() {
        let result = MonitoringMeasurementInputValidator.validate(
            kind: .temperature,
            primary: "37,5",
            secondary: nil
        )
        guard case let .success(validated) = result else {
            return XCTFail("Expected valid temperature")
        }
        XCTAssertEqual(validated.primaryValue, 37.5, accuracy: 0.001)
        XCTAssertNil(validated.secondaryValue)
        XCTAssertEqual(validated.unit, "°C")
    }

    func testGlucoseAndHeartRateRequireSingleInteger() {
        let glucose = MonitoringMeasurementInputValidator.validate(
            kind: .bloodGlucose,
            primary: "110",
            secondary: nil
        )
        guard case let .success(glucoseValue) = glucose else {
            return XCTFail("Expected valid glucose")
        }
        XCTAssertEqual(glucoseValue.primaryValue, 110)
        XCTAssertEqual(glucoseValue.unit, "mg/dL")

        let heartRate = MonitoringMeasurementInputValidator.validate(
            kind: .heartRate,
            primary: "72",
            secondary: nil
        )
        guard case let .success(heartRateValue) = heartRate else {
            return XCTFail("Expected valid heart rate")
        }
        XCTAssertEqual(heartRateValue.primaryValue, 72)
        XCTAssertEqual(heartRateValue.unit, "bpm")
    }
}
