import SwiftUI

struct MissedDoseSheetState: Identifiable {
    let candidate: MissedDoseCandidate
    let operationId: UUID
    let operationKey: OperationKey?

    var id: String { candidate.id }
}

struct MissedDoseIntakeSheet: View {
    private enum TimeSelection {
        case now
        case scheduled
        case custom
    }

    let candidate: MissedDoseCandidate
    let now: Date
    let onConfirm: (Date, MissedDoseNextAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTime: Date
    @State private var selectedMode: TimeSelection = .scheduled
    @State private var nextAction: MissedDoseNextAction = .keepSchedule

    init(
        candidate: MissedDoseCandidate,
        now: Date = Date(),
        onConfirm: @escaping (Date, MissedDoseNextAction) -> Void
    ) {
        self.candidate = candidate
        self.now = now
        self.onConfirm = onConfirm
        _selectedTime = State(initialValue: candidate.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choiceButton(
                        title: "Assunto adesso",
                        isSelected: selectedMode == .now
                    ) {
                        selectedMode = .now
                        selectedTime = now
                    }

                    choiceButton(
                        title: "Assunto all'orario di assunzione",
                        isSelected: selectedMode == .scheduled
                    ) {
                        selectedMode = .scheduled
                        selectedTime = candidate.scheduledAt
                    }

                    DatePicker(
                        "Scegli orario di assunzione",
                        selection: Binding(
                            get: { selectedTime },
                            set: { newValue in
                                selectedMode = .custom
                                selectedTime = newValue
                            }
                        ),
                        displayedComponents: [.hourAndMinute]
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                } header: {
                    Text("Quando l'hai assunta?")
                }

                if shouldAskNextDoseAction {
                    Section {
                        choiceButton(
                            title: MissedDoseNextAction.postponeByStandardInterval.title,
                            isSelected: nextAction == .postponeByStandardInterval
                        ) {
                            nextAction = .postponeByStandardInterval
                        }

                        choiceButton(
                            title: MissedDoseNextAction.keepSchedule.title,
                            isSelected: nextAction == .keepSchedule
                        ) {
                            nextAction = .keepSchedule
                        }
                    } header: {
                        Text("Prossima dose")
                    } footer: {
                        Text("Se cambi l'orario di questa assunzione, puoi spostare solo la prossima dose mantenendo l'intervallo abituale.")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(candidate.therapy.medicine.nome)
                            .font(.headline)
                            .lineLimit(1)
                        Text(timeFormatter.string(from: candidate.scheduledAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onConfirm(selectedTime, shouldAskNextDoseAction ? nextAction : .keepSchedule)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(sheetDetentHeight), .large])
        .presentationDragIndicator(.visible)
    }

    private var shouldAskNextDoseAction: Bool {
        guard candidate.nextScheduledAt != nil else { return false }
        return minuteBucket(for: selectedTime) != minuteBucket(for: candidate.scheduledAt)
    }

    private var sheetDetentHeight: CGFloat {
        shouldAskNextDoseAction ? 620 : 460
    }

    @ViewBuilder
    private func choiceButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func minuteBucket(for date: Date) -> Int {
        Int(date.timeIntervalSince1970 / 60)
    }

    private var timeFormatter: DateFormatter {
        Self.sheetTimeFormatter
    }
    private static let sheetTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}
