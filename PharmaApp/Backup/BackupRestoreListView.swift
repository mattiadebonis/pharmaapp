import SwiftUI

struct BackupRestoreListView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var backupCoordinator: BackupCoordinator

    @State private var snapshotPendingRestore: BackupSnapshotDescriptor?

    var body: some View {
        List {
            if backupCoordinator.snapshots.isEmpty {
                Section {
                    Text("Nessun backup disponibile su iCloud.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Backup disponibili") {
                    ForEach(backupCoordinator.snapshots) { snapshot in
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
                        .disabled(backupCoordinator.status.isBusy)
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
                    let didRestore = await backupCoordinator.restore(snapshot)
                    if didRestore {
                        dismiss()
                    }
                }
            }
            Button("Annulla", role: .cancel) {
                snapshotPendingRestore = nil
            }
        } message: { snapshot in
            Text("Backup del \(dateFormatter.string(from: snapshot.createdAt)).")
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
}

#Preview {
    NavigationStack {
        BackupRestoreListView()
    }
    .environmentObject(BackupCoordinator())
}
