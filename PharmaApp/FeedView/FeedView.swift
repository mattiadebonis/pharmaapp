//
//  FeedView.swift
//  PharmaApp
//
//  Created by Mattia De Bonis on 02/01/25.
//

import SwiftUI
import CoreData

struct FeedView: View {
    @Environment(\.managedObjectContext) var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicines())
    var medicines: FetchedResults<Medicine>
    @FetchRequest(fetchRequest: Option.extractOptions())
    private var options: FetchedResults<Option>
    
    @ObservedObject var viewModel: FeedViewModel
    @State private var selectedMedicine: Medicine?

    var body: some View {
        let sections = computeSections()

        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !sections.oggi.isEmpty {
                        Text("Oggi (\(sections.oggi.count))")
                            .font(.title2.bold())
                            .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(sections.oggi) { medicine in
                                row(for: medicine)
                            }
                        }
                    }

                    if !sections.watch.isEmpty {
                        Text("Da tenere d’occhio (\(sections.watch.count))")
                            .font(.title2.bold())
                            .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(sections.watch) { medicine in
                                row(for: medicine)
                            }
                        }
                    }

                    if !sections.ok.isEmpty {
                        Text("Tutto ok (\(sections.ok.count))")
                            .font(.title2.bold())
                            .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(sections.ok) { medicine in
                                row(for: medicine)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedMedicine != nil },
            set: { newValue in
                if !newValue { selectedMedicine = nil }
            }
        )) {
            if let medicine = selectedMedicine {
                if let package = getPackage(for: medicine) {
                    MedicineDetailView(
                        medicine: medicine,
                        package: package
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                } else {
                    VStack(spacing: 12) {
                        Text("Completa i dati del medicinale")
                            .font(.headline)
                        Text("Aggiungi una confezione dalla schermata dettaglio per utilizzare le funzioni avanzate.")
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .presentationDetents([.medium])
                }
            }
        }
        .onChange(of: selectedMedicine) { newValue in
            if (newValue == nil) {
                viewModel.clearSelection() 
            }
        }
    }

    // MARK: - Row builder (gestures + card)
    private func row(for medicine: Medicine) -> some View {
        MedicineRowView(
            medicine: medicine,
            isSelected: viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine),
            toggleSelection: { viewModel.toggleSelection(for: medicine) }
        )
        .padding(8)
        .background(viewModel.isSelecting && viewModel.selectedMedicines.contains(medicine) ? Color.gray.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: medicine)
                } else {
                    selectedMedicine = medicine
                }
            }
        )
        .gesture(
            LongPressGesture().onEnded { _ in
                selectedMedicine = medicine
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        )
        .accessibilityIdentifier("MedicineRow_\(medicine.objectID)")
    }

    // MARK: - New sorting algorithm (sections)
    private func computeSections() -> (oggi: [Medicine], watch: [Medicine], ok: [Medicine]) {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let option = options.first
        let now = Date()
        let cal = Calendar.current
        let endOfDay: Date = {
            let start = cal.startOfDay(for: now)
            return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()

        func nextOccurrenceToday(for m: Medicine) -> Date? {
            guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
            var best: Date? = nil
            for t in therapies {
                let rule = rec.parseRecurrenceString(t.rrule ?? "")
                let startDate = t.start_date ?? now
                if let d = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: t.doses as NSSet?) {
                    if cal.isDate(d, inSameDayAs: now) && d <= endOfDay {
                        if best == nil || d < best! { best = d }
                    }
                }
            }
            return best
        }

        func autonomyDays(for m: Medicine) -> Int? {
            guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
            var totalLeft: Double = 0
            var totalDaily: Double = 0
            for t in therapies {
                totalLeft += Double(t.leftover())
                totalDaily += t.stimaConsumoGiornaliero(recurrenceManager: rec)
            }
            guard totalDaily > 0 else { return nil }
            return Int(totalLeft / totalDaily)
        }

        func isLowStock(_ m: Medicine) -> Bool {
            guard let opt = option else { return false }
            return m.isInEsaurimento(option: opt, recurrenceManager: rec)
        }

        var oggi: [Medicine] = []
        var watch: [Medicine] = []
        var ok: [Medicine] = []

        for m in medicines {
            if let _ = nextOccurrenceToday(for: m) {
                oggi.append(m)
            } else if isLowStock(m) {
                watch.append(m)
            } else {
                ok.append(m)
            }
        }

        oggi.sort { (m1, m2) in
            let d1 = nextOccurrenceToday(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrenceToday(for: m2) ?? Date.distantFuture
            return d1 < d2
        }

        watch.sort { (m1, m2) in
            let a1 = autonomyDays(for: m1) ?? Int.max
            let a2 = autonomyDays(for: m2) ?? Int.max
            if a1 == a2 {
                return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
            }
            return a1 < a2
        }

        ok.sort { $0.nome.localizedCaseInsensitiveCompare($1.nome) == .orderedAscending }

        return (oggi, watch, ok)
    }

    func getPackage(for medicine: Medicine) -> Package? {
        if let therapies = medicine.therapies, let therapy = therapies.first {
            return therapy.package
        }
        if let logs = medicine.logs {
            let purchaseLogs = logs.filter { $0.type == "purchase" }
            if let package = purchaseLogs.sorted(by: { $0.timestamp > $1.timestamp }).first?.package {
                return package
            }
        }
        if let package = medicine.packages.first {
            return package
        }
        return nil
    }
}
