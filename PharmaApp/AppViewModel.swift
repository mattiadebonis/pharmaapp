//
//  AppViewModel.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 02/01/25.
//

import SwiftUI

class AppViewModel: ObservableObject {
    @Published var isSearchIndexPresented: Bool = false
    @Published var isStocksIndexPresented: Bool = false
    @Published var isProfilePresented: Bool = false
    @Published var suggestNearestPharmacies: Bool = false
    @Published var query: String = ""
}
