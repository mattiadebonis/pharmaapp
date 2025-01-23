//
//  DayTogglePill.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 16/01/25.
//

import SwiftUI

struct DayTogglePill: View {
    let day: String
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            Text(day)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundColor(isSelected ? .white : .blue)
                .background(isSelected ? Color.blue : Color.clear)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.blue, lineWidth: 1)
                )
        }
        .animation(.easeInOut, value: isSelected)
    }
}
