//
//  PharmaAppTests.swift
//  PharmaAppTests
//
//  Created by Mattia De bonis on 09/12/24.
//

import CoreData
import Testing
@testable import PharmaApp

struct PharmaAppTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func therapySummaryIncludesPrescribingDoctor() throws {
        let container = try TestCoreDataFactory.makeContainer()
        let context = container.viewContext

        let medicine = try TestCoreDataFactory.makeMedicine(context: context)
        medicine.nome = "Cardioaspirina"

        let package = try TestCoreDataFactory.makePackage(context: context, medicine: medicine, numero: 30)
        package.tipologia = "compressa"
        package.unita = "mg"

        let therapy = try TestCoreDataFactory.makeTherapy(context: context, medicine: medicine)
        therapy.package = package
        therapy.person = try makePerson(context: context, name: "Mario")
        therapy.prescribingDoctor = try makeDoctor(context: context, firstName: "Lucia", lastName: "Bianchi")
        therapy.rrule = "FREQ=DAILY"

        let dose = try makeDose(context: context, therapy: therapy)
        dose.time = Calendar.current.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: Date()
        ) ?? Date()

        let builder = TherapySummaryBuilder(recurrenceManager: RecurrenceManager(context: context))
        let summary = builder.summary(for: therapy)

        #expect(summary.contains("Medico prescrittore: Lucia Bianchi"))
    }

    private func makePerson(context: NSManagedObjectContext, name: String) throws -> Person {
        guard let entity = NSEntityDescription.entity(forEntityName: "Person", in: context) else {
            throw NSError(domain: "PharmaAppTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Person entity in test context."])
        }
        let person = Person(entity: entity, insertInto: context)
        person.id = UUID()
        person.nome = name
        person.is_account = false
        return person
    }

    private func makeDoctor(context: NSManagedObjectContext, firstName: String, lastName: String) throws -> Doctor {
        guard let entity = NSEntityDescription.entity(forEntityName: "Doctor", in: context) else {
            throw NSError(domain: "PharmaAppTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing Doctor entity in test context."])
        }
        let doctor = Doctor(entity: entity, insertInto: context)
        doctor.id = UUID()
        doctor.nome = firstName
        doctor.cognome = lastName
        return doctor
    }

    private func makeDose(context: NSManagedObjectContext, therapy: Therapy) throws -> Dose {
        guard let entity = NSEntityDescription.entity(forEntityName: "Dose", in: context) else {
            throw NSError(domain: "PharmaAppTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing Dose entity in test context."])
        }
        let dose = Dose(entity: entity, insertInto: context)
        dose.id = UUID()
        dose.amount = NSNumber(value: 1)
        dose.therapy = therapy
        return dose
    }

}
