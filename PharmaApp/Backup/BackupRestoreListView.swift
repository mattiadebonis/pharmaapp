import SwiftUI

struct BackupRestoreListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appDataStore: AppDataStore

    @State private var snapshotPendingRestore: BackupSnapshotDescriptor?
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
        List {
            if backupState.snapshots.isEmpty {
                Section {
                    Text("Nessun backup disponibile su iCloud.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Backup disponibili") {
                    ForEach(backupState.snapshots) { snapshot in
                        Button {
                            snapshotPendingRestore = snapshot
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.displayName)
                                    .foregroundStyle(.primary)
                                Text(snapshotSummary(for: snapshot))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(backupState.status.isBusy)
                    }
                }
            }

            Section {
                Text("Il restore sostituisce tutti i dati locali.")
                Text("Se l'utente PharmaApp non coincide con il backup selezionato, il restore non e consentito.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Ripristina backup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .alert(
            "Ripristinare questo backup?",
            isPresented: Binding(
                get: { snapshotPendingRestore != nil },
                set: { isPresented in
                    if !isPresented {
                        snapshotPendingRestore = nil
                    }
                }
            ),
            presenting: snapshotPendingRestore
        ) { snapshot in
            Button("Ripristina", role: .destructive) {
                Task {
                    let didRestore = await appDataStore.provider.backup.restore(snapshotId: snapshot.id)
                    if didRestore {
                        dismiss()
                    }
                    refreshState()
                }
            }
            Button("Annulla", role: .cancel) {
                snapshotPendingRestore = nil
            }
        } message: { snapshot in
            Text("Backup del \(dateFormatter.string(from: snapshot.createdAt)).")
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

    private func snapshotSummary(for snapshot: BackupSnapshotDescriptor) -> String {
        let size = ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file)
        return "\(dateFormatter.string(from: snapshot.createdAt)) • \(size)"
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func refreshState() {
        backupState = appDataStore.provider.backup.state
    }

    private func observeBackupState() async {
        for await state in appDataStore.provider.backup.observeState() {
            backupState = state
        }
    }
}

#Preview {
    NavigationStack {
        BackupRestoreListView()
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
