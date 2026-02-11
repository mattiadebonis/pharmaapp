//
//  EventTimeMenu.swift
//  PharmaApp
//
//  Created by Codex on 06/02/26.
//

import SwiftUI

struct EventTimeMenu: View {
    let option: Option
    @Binding var time: Date

    var body: some View {
        Menu {
            ForEach(EventTimeKind.allCases) { kind in
                Button(kind.label) {
                    let updated = EventTimeSettings.time(for: option, kind: kind, base: time)
                    time = updated
                }
            }
        } label: {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Seleziona evento")
    }
}
