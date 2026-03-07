//
//  TherapyFormViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation

struct DoseEntry: Identifiable, Hashable {
    var id: UUID = UUID()
    var time: Date
    var amount: Double

    init(id: UUID = UUID(), time: Date, amount: Double) {
        self.id = id
        self.time = time
        self.amount = amount
    }
}

extension DoseEntry {
    static func fromDose(_ dose: Dose) -> DoseEntry {
        DoseEntry(time: dose.time, amount: dose.amountValue)
    }
}
