import XCTest
@testable import PharmaApp

final class CabinetCustomFilterLanguageTests: XCTestCase {
    private let parser = CabinetCustomFilterQueryParser()
    private let evaluator = CabinetCustomFilterEvaluator()

    func testImplicitAndAndPrecedence() throws {
        let expression = try parser.parse("stock:low OR stock:out AND rx:true")

        let lowNoRx = CabinetCustomFilterContext(
            name: "Tachipirina",
            labels: [],
            stock: .low,
            hasTherapy: true,
            requiresPrescription: false,
            cabinetNames: ["Casa"],
            deadline: .ok
        )
        XCTAssertTrue(evaluator.matches(expression, in: lowNoRx))

        let outNoRx = CabinetCustomFilterContext(
            name: "Bentelan",
            labels: [],
            stock: .out,
            hasTherapy: true,
            requiresPrescription: false,
            cabinetNames: ["Casa"],
            deadline: .ok
        )
        XCTAssertFalse(evaluator.matches(expression, in: outNoRx))

        let outRx = CabinetCustomFilterContext(
            name: "Bentelan",
            labels: [],
            stock: .out,
            hasTherapy: true,
            requiresPrescription: true,
            cabinetNames: ["Casa"],
            deadline: .ok
        )
        XCTAssertTrue(evaluator.matches(expression, in: outRx))
    }

    func testAliasesAndQuotedValues() throws {
        let expression = try parser.parse("scorte:in_esaurimento AND armadietto:\"Casa Principale\"")

        let matching = CabinetCustomFilterContext(
            name: "Moment",
            labels: ["Viaggio"],
            stock: .low,
            hasTherapy: false,
            requiresPrescription: false,
            cabinetNames: ["Casa Principale"],
            deadline: .none
        )

        XCTAssertTrue(evaluator.matches(expression, in: matching))
    }

    func testInvalidSyntaxReturnsPosition() {
        XCTAssertThrowsError(try parser.parse("stock:low AND (rx:true")) { error in
            guard let languageError = error as? CabinetCustomFilterLanguageError else {
                XCTFail("Expected CabinetCustomFilterLanguageError")
                return
            }
            XCTAssertGreaterThanOrEqual(languageError.position, 0)
            XCTAssertTrue(languageError.message.contains("Parentesi chiusa"))
        }
    }

    func testDeadlineAndNotExpression() throws {
        let expression = try parser.parse("deadline:expired AND NOT terapia:true")

        let expiredNoTherapy = CabinetCustomFilterContext(
            name: "Aspirina",
            labels: ["Emergenza"],
            stock: .ok,
            hasTherapy: false,
            requiresPrescription: false,
            cabinetNames: [],
            deadline: .expired
        )
        XCTAssertTrue(evaluator.matches(expression, in: expiredNoTherapy))

        let expiredWithTherapy = CabinetCustomFilterContext(
            name: "Aspirina",
            labels: ["Emergenza"],
            stock: .ok,
            hasTherapy: true,
            requiresPrescription: false,
            cabinetNames: [],
            deadline: .expired
        )
        XCTAssertFalse(evaluator.matches(expression, in: expiredWithTherapy))
    }

    func testNestedParenthesesAndImplicitAnd() throws {
        let expression = try parser.parse("(stock:low OR stock:out) (rx:true OR therapy:true)")

        let matching = CabinetCustomFilterContext(
            name: "Bentelan",
            labels: ["Urgente"],
            stock: .out,
            hasTherapy: false,
            requiresPrescription: true,
            cabinetNames: ["Casa"],
            deadline: .soon
        )
        XCTAssertTrue(evaluator.matches(expression, in: matching))

        let nonMatching = CabinetCustomFilterContext(
            name: "Paracetamolo",
            labels: ["Casa"],
            stock: .ok,
            hasTherapy: true,
            requiresPrescription: true,
            cabinetNames: ["Casa"],
            deadline: .ok
        )
        XCTAssertFalse(evaluator.matches(expression, in: nonMatching))
    }

    func testAllTextAndBooleanFields() throws {
        let expression = try parser.parse(
            "name:aspirina AND label:emergenza AND cabinet:casa AND ricetta:si AND terapia:no"
        )

        let matching = CabinetCustomFilterContext(
            name: "Aspirina C",
            labels: ["Emergenza", "Viaggio"],
            stock: .low,
            hasTherapy: false,
            requiresPrescription: true,
            cabinetNames: ["Casa Principale"],
            deadline: .ok
        )
        XCTAssertTrue(evaluator.matches(expression, in: matching))
    }
}
