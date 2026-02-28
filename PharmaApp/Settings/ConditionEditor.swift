//
//  ConditionEditor.swift
//  PharmaApp
//
//  Created by Codex on 28/02/26.
//

import SwiftUI

enum ConditionListFormatter {
    static func parsed(from rawValue: String?) -> [String] {
        guard let rawValue else { return [] }

        let chunks = rawValue.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
        var output: [String] = []

        for chunk in chunks {
            guard let normalized = normalized(chunk) else { continue }
            if !output.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                output.append(normalized)
            }
        }

        return output
    }

    static func serialized(from values: [String]) -> String? {
        let normalizedValues = parsed(from: values.joined(separator: "\n"))
        return normalizedValues.isEmpty ? nil : normalizedValues.joined(separator: "\n")
    }

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct ConditionsEditorSection: View {
    @Binding var conditions: [String]

    @State private var editorContext: ConditionEditorContext?

    var body: some View {
        Section(header: Text("Condizioni")) {
            if conditions.isEmpty {
                Text("Nessuna condizione inserita.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tocca una condizione per modificarla o rimuoverla.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .top)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(Array(conditions.enumerated()), id: \.offset) { index, condition in
                            ConditionCard(
                                title: condition,
                                onEdit: {
                                    editorContext = .editing(index: index, value: condition)
                                },
                                onDelete: {
                                    removeCondition(at: index)
                                }
                            )
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                editorContext = .new
            } label: {
                Label("Aggiungi condizione", systemImage: "plus.circle.fill")
            }
        }
        .sheet(item: $editorContext) { context in
            ConditionEditorSheet(
                title: context.title,
                actionTitle: context.actionTitle,
                initialValue: context.initialValue,
                existingConditions: conditions,
                editingIndex: context.index,
                onSave: { newValue in
                    saveCondition(newValue, editingIndex: context.index)
                },
                onDelete: context.index == nil ? nil : {
                    if let index = context.index {
                        removeCondition(at: index)
                    }
                }
            )
        }
    }

    private func saveCondition(_ value: String, editingIndex: Int?) {
        guard let normalized = ConditionListFormatter.normalized(value) else { return }

        if let editingIndex, conditions.indices.contains(editingIndex) {
            conditions[editingIndex] = normalized
        } else {
            conditions.append(normalized)
        }

        if let serialized = ConditionListFormatter.serialized(from: conditions) {
            conditions = ConditionListFormatter.parsed(from: serialized)
        } else {
            conditions = []
        }
    }

    private func removeCondition(at index: Int) {
        guard conditions.indices.contains(index) else { return }
        conditions.remove(at: index)
    }
}

private struct ConditionCard: View {
    let title: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ConditionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let actionTitle: String
    let existingConditions: [String]
    let editingIndex: Int?
    let onSave: (String) -> Void
    let onDelete: (() -> Void)?

    @State private var draft: String
    @State private var errorMessage: String?

    init(
        title: String,
        actionTitle: String,
        initialValue: String,
        existingConditions: [String],
        editingIndex: Int?,
        onSave: @escaping (String) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.existingConditions = existingConditions
        self.editingIndex = editingIndex
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Condizione")) {
                    TextField("Es. Ipertensione", text: $draft, axis: .vertical)
                        .lineLimit(1...3)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Rimuovi condizione")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        save()
                    }
                }
            }
        }
        .presentationDetents(onDelete == nil ? [.fraction(0.32), .medium] : [.fraction(0.42), .medium])
    }

    private func save() {
        guard let normalized = ConditionListFormatter.normalized(draft) else {
            errorMessage = "Inserisci una condizione."
            return
        }

        if existingConditions.enumerated().contains(where: { index, value in
            guard index != editingIndex else { return false }
            return value.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            errorMessage = "Questa condizione e' gia presente."
            return
        }

        onSave(normalized)
        dismiss()
    }
}

private struct ConditionEditorContext: Identifiable {
    let id: String
    let index: Int?
    let initialValue: String

    var title: String {
        index == nil ? "Nuova condizione" : "Modifica condizione"
    }

    var actionTitle: String {
        index == nil ? "Aggiungi" : "Salva"
    }

    static let new = ConditionEditorContext(id: "new", index: nil, initialValue: "")

    static func editing(index: Int, value: String) -> ConditionEditorContext {
        ConditionEditorContext(id: "edit-\(index)", index: index, initialValue: value)
    }
}
