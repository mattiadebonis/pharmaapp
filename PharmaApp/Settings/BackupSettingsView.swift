import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var backupCoordinator: BackupCoordinator

    @State private var isRestoreSheetPresented = false

    var body: some View {
        Form {
            Section(
                header: Label("Backup iCloud", systemImage: "icloud"),
                footer: Text("Il backup usa l'iCloud del dispositivo, non l'account PharmaApp.")
            ) {
                LabeledContent("Stato iCloud", value: backupCoordinator.cloudAvailability.description)
                LabeledContent("Stato backup", value: backupCoordinator.status.description)
                LabeledContent("Snapshot disponibili", value: "\(backupCoordinator.snapshots.count)")
                LabeledContent("Ultimo backup", value: lastBackupText)

                Toggle("Backup automatico", isOn: $backupCoordinator.backupEnabled)
                    .disabled(backupCoordinator.status.isBusy || backupCoordinator.cloudAvailability != .available)

                Button("Aggiorna backup") {
                    Task {
                        await backupCoordinator.performManualBackup()
                    }
                }
                .disabled(backupCoordinator.status.isBusy || backupCoordinator.cloudAvailability != .available)

                Button {
                    isRestoreSheetPresented = true
                } label: {
                    Text("Ripristina backup")
                }
                .disabled(
                    backupCoordinator.status.isBusy
                    || backupCoordinator.snapshots.isEmpty
                    || backupCoordinator.cloudAvailability != .available
                )

                if backupCoordinator.status.isBusy {
                    ProgressView()
                }
            }

            if let lastError = backupCoordinator.lastErrorMessage, !lastError.isEmpty {
                Section {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Il restore sostituisce tutti i dati locali.")
                Text("Se l'utente PharmaApp non coincide con il backup selezionato, il restore non e consentito.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Backup iCloud")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isRestoreSheetPresented) {
            NavigationStack {
                BackupRestoreListView()
            }
        }
    }

    private var lastBackupText: String {
        guard let date = backupCoordinator.lastSuccessfulBackupAt else { return "Mai" }
        return Self.timestampFormatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    NavigationStack {
        BackupSettingsView()
    }
    .environmentObject(BackupCoordinator())
}
