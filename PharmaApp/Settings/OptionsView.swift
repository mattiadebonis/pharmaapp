//
//  OptionsView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 23/01/25.
//

import SwiftUI

struct OptionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            TherapySettingsSectionsView()
        }
        .navigationTitle("Opzioni")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fine") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        OptionsView()
    }
    .environmentObject(
        AppDataStore(
            provider: CoreDataAppDataProvider(
                authGateway: FirebaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
            )
        )
    )
}
