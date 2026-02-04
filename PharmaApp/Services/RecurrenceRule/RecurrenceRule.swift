//
//  RecurrenceRule.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 27/12/24.
//

import Foundation

public struct RecurrenceRule {
    public var freq: String
    public var interval: Int
    public var until: Date?
    public var count: Int?
    public var byDay: [String]
    public var byMonth: [Int]
    public var byMonthDay: [Int]
    public var wkst: String?
    public var exdates: [Date]
    public var rdates: [Date]

    public init(
        freq: String,
        interval: Int = 1,
        until: Date? = nil,
        count: Int? = nil,
        byDay: [String] = [],
        byMonth: [Int] = [],
        byMonthDay: [Int] = [],
        wkst: String? = nil,
        exdates: [Date] = [],
        rdates: [Date] = []
    ) {
        self.freq = freq
        self.interval = interval
        self.until = until
        self.count = count
        self.byDay = byDay
        self.byMonth = byMonth
        self.byMonthDay = byMonthDay
        self.wkst = wkst
        self.exdates = exdates
        self.rdates = rdates
    }
}
