//
//  RecurrenceRule.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation

struct RecurrenceRule {
    var freq: String
    var interval: Int = 1
    var until: Date? = nil
    var count: Int? = nil
    var byDay: [String] = []
    var byMonth: [Int] = []
    var byMonthDay: [Int] = []
    var wkst: String? = nil
    var exdates: [Date] = []
    var rdates: [Date] = []
}