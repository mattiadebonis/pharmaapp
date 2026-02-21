import XCTest
@testable import PharmaApp

final class PrescriptionMessageTemplateRendererTests: XCTestCase {
    func testIsValidTemplateRequiresBothPlaceholders() {
        let valid = "Ciao {medico}, ho bisogno di {medicinali}."
        let missingDoctor = "Ciao, ho bisogno di {medicinali}."
        let missingMedicines = "Ciao {medico}, ho bisogno di una ricetta."

        XCTAssertTrue(PrescriptionMessageTemplateRenderer.isValidTemplate(valid))
        XCTAssertFalse(PrescriptionMessageTemplateRenderer.isValidTemplate(missingDoctor))
        XCTAssertFalse(PrescriptionMessageTemplateRenderer.isValidTemplate(missingMedicines))
    }

    func testRenderSingleMedicine() {
        let template = "Ciao {medico}, mi serve {medicinali}."

        let rendered = PrescriptionMessageTemplateRenderer.render(
            template: template,
            doctorName: "Dott. Bianchi",
            medicineNames: ["Augmentin"]
        )

        XCTAssertEqual(rendered, "Ciao Dott. Bianchi, mi serve Augmentin.")
    }

    func testRenderMultipleMedicinesWithCommaSeparatedList() {
        let template = "Ciao {medico}, mi servono {medicinali}."

        let rendered = PrescriptionMessageTemplateRenderer.render(
            template: template,
            doctorName: "Dott.ssa Neri",
            medicineNames: ["Augmentin", "Tachipirina", "Brufen"]
        )

        XCTAssertEqual(rendered, "Ciao Dott.ssa Neri, mi servono Augmentin, Tachipirina, Brufen.")
    }

    func testRenderFallsBackToDoctorPlaceholderDefaultWhenDoctorNameIsEmpty() {
        let template = "Ciao {medico}, mi serve {medicinali}."

        let rendered = PrescriptionMessageTemplateRenderer.render(
            template: template,
            doctorName: "   ",
            medicineNames: ["Aspirina"]
        )

        XCTAssertEqual(rendered, "Ciao Dottore, mi serve Aspirina.")
    }

    func testResolvedTemplateFallsBackToDefaultWhenCustomTemplateIsInvalid() {
        let invalidTemplate = "Ciao medico, ricetta per medicine"

        let rendered = PrescriptionMessageTemplateRenderer.render(
            template: invalidTemplate,
            doctorName: "Dott. Verdi",
            medicineNames: ["Aspirina"]
        )

        XCTAssertTrue(rendered.contains("Gentile Dott. Verdi"))
        XCTAssertTrue(rendered.contains("Aspirina"))
    }
}
