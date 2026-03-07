import SwiftUI

struct BackupSettingsView: View {
    @EnvironmentObject private var appDataStore: AppDataStore

    @State private var isRestoreSheetPresented = false
    @State private var backupState = BackupGatewayState(
        status: .idle,
        cloudAvailability: .unavailable,
        snapshots: [],
        lastSuccessfulBackupAt: nil,
        lastErrorMessage: nil,
        backupEnabled: false,
        restoreRevision: 0
    )
    @State private var didStartObservation = false

    var body: some View {
        Form {
            Section(
                header: Label("Backup iCloud", systemImage: "icloud"),
                footer: Text("Il backup usa l'iCloud del dispositivo, non l'account PharmaApp.")
            ) {
                LabeledContent("Stato iCloud", value: backupState.cloudAvailability.description)
                LabeledContent("Stato backup", value: backupState.status.description)
                LabeledContent("Snapshot disponibili", value: "\(backupState.snapshots.count)")
                LabeledContent("Ultimo backup", value: lastBackupText)

                Toggle(
                    "Backup automatico",
                    isOn: Binding(
                        get: { backupState.backupEnabled },
                        set: { newValue in
                            appDataStore.provider.backup.setEnabled(newValue)
                            refreshState()
                        }
                    )
                )
                .disabled(backupState.status.isBusy || backupState.cloudAvailability != .available)

                Button("Aggiorna backup") {
                    Task {
                        _ = await appDataStore.provider.backup.performManualBackup()
                        refreshState()
                    }
                }
                .disabled(backupState.status.isBusy || backupState.cloudAvailability != .available)

                Button {
                    isRestoreSheetPresented = true
                } label: {
                    Text("Ripristina backup")
                }
                .disabled(
                    backupState.status.isBusy
                    || backupState.snapshots.isEmpty
                    || backupState.cloudAvailability != .available
                )

                if backupState.status.isBusy {
                    ProgressView()
                }
            }

            if let lastError = backupState.lastErrorMessage, !lastError.isEmpty {
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
        .onAppear {
            refreshState()
            appDataStore.provider.backup.refreshSnapshots()
            refreshState()
        }
        .task {
            guard !didStartObservation else { return }
            didStartObservation = true
            await observeBackupState()
        }
    }

    private var lastBackupText: String {
        guard let date = backupState.lastSuccessfulBackupAt else { return "Mai" }
        return Self.timestampFormatter.string(from: date)
    }

    private func refreshState() {
        backupState = appDataStore.provider.backup.state
    }

    private func observeBackupState() async {
        for await state in appDataStore.provider.backup.observeState() {
            backupState = state
        }
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
    .environmentObject(
        AppDataStore(
            provider: CoreDataAppDataProvider(
                authGateway: FirebaseAuthGatewayAdapter(),
                backupGateway: ICloudBackupGatewayAdapter(coordinator: BackupCoordinator())
            )
        )
    )
}
