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
    // Traccia i Log per forzare il refresh della lista quando si registra un'assunzione/acquisto
    @FetchRequest(fetchRequest: Log.extractLogs())
    private var logs: FetchedResults<Log>
    
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
        // Ricostruisce la vista quando cambia il numero di log (assunzioni/acquisti)
        .id(logs.count)
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
        // Usa gesture con including: .gesture per non interferire con i pulsanti interni
        .gesture(
            TapGesture().onEnded {
                if viewModel.isSelecting {
                    viewModel.toggleSelection(for: medicine)
                } else {
                    selectedMedicine = medicine
                }
            }, including: .gesture
        )
        .gesture(
            LongPressGesture().onEnded { _ in
                selectedMedicine = medicine
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }, including: .gesture
        )
        .accessibilityIdentifier("MedicineRow_\(medicine.objectID)")
    }

    // MARK: - New sorting algorithm (sections)
    private func computeSections() -> (oggi: [Medicine], watch: [Medicine], ok: [Medicine]) {
        let rec = RecurrenceManager(context: PersistenceController.shared.container.viewContext)
        let now = Date()
        let cal = Calendar.current
        let endOfDay: Date = {
            let start = cal.startOfDay(for: now)
            return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? now
        }()

        // Calcolo unità rimanenti per una medicine, basato su logs e package
        func remainingUnits(for m: Medicine) -> Int? {
            guard let pkg = getPackage(for: m), let logs = m.logs else { return nil }
            let purchases = logs.filter { $0.type == "purchase" && $0.package == pkg }.count
            let intakes   = logs.filter { $0.type == "intake" && $0.package == pkg }.count
            return purchases * Int(pkg.numero) - intakes
        }

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

        // Prossima assunzione (anche oltre oggi): usata come primo criterio d'ordinamento
        func nextOccurrence(for m: Medicine) -> Date? {
            guard let therapies = m.therapies, !therapies.isEmpty else { return nil }
            var best: Date? = nil
            for t in therapies {
                let rule = rec.parseRecurrenceString(t.rrule ?? "")
                let startDate = t.start_date ?? now
                if let d = rec.nextOccurrence(rule: rule, startDate: startDate, after: now, doses: t.doses as NSSet?) {
                    if best == nil || d < best! { best = d }
                }
            }
            return best
        }

        // MARK: - Pianificazione: conteggio dosi previste oggi
        func icsCode(for date: Date) -> String {
            let weekday = cal.component(.weekday, from: date)
            switch weekday { case 1: return "SU"; case 2: return "MO"; case 3: return "TU"; case 4: return "WE"; case 5: return "TH"; case 6: return "FR"; case 7: return "SA"; default: return "MO" }
        }

        func occursToday(_ t: Therapy) -> Bool {
            let rule = rec.parseRecurrenceString(t.rrule ?? "")
            let start = t.start_date ?? now
            // Se la therapy parte dopo oggi, non è prevista oggi
            if start > endOfDay { return false }
            // Rispetta eventuale UNTIL
            if let until = rule.until, cal.startOfDay(for: until) < cal.startOfDay(for: now) { return false }

            let freq = rule.freq.uppercased()
            let interval = rule.interval ?? 1

            switch freq {
            case "DAILY":
                let startSOD = cal.startOfDay(for: start)
                let todaySOD = cal.startOfDay(for: now)
                if let days = cal.dateComponents([.day], from: startSOD, to: todaySOD).day, days >= 0 {
                    return days % max(1, interval) == 0
                }
                return false

            case "WEEKLY":
                let todayCode = icsCode(for: now)
                let byDays = rule.byDay.isEmpty ? ["MO","TU","WE","TH","FR","SA","SU"] : rule.byDay
                guard byDays.contains(todayCode) else { return false }

                // Verifica intervallo settimanale
                let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: start)) ?? start
                let todayWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
                if let weeks = cal.dateComponents([.weekOfYear], from: startWeek, to: todayWeek).weekOfYear, weeks >= 0 {
                    return weeks % max(1, interval) == 0
                }
                return false

            default:
                return false
            }
        }

        func scheduledDosesTodayCount(for t: Therapy) -> Int {
            guard occursToday(t) else { return 0 }
            let count = t.doses?.count ?? 1
            return max(0, count)
        }

        func scheduledDosesTodayCount(for m: Medicine) -> Int {
            guard let therapies = m.therapies, !therapies.isEmpty else { return 0 }
            return therapies.reduce(0) { $0 + scheduledDosesTodayCount(for: $1) }
        }

        func intakeLogsTodayCount(for m: Medicine) -> Int {
            // Usa i log fetchati e filtra per medicina + oggi
            return logs.filter { $0.medicine == m && $0.type == "intake" && cal.isDate($0.timestamp, inSameDayAs: now) }.count
        }

        // Soglie fisse per classificazione
        // <5 unità  => sezione "Oggi"
        // <7 unità  => sezione "Da tenere d'occhio"
        // Nota: da ora "Oggi" considera SOLO dosi odierne rimanenti, non la criticità scorte
        func isWatch(_ m: Medicine) -> Bool {
            // Se ha terapie: usa la copertura (soglia dalle Options)
            if let therapies = m.therapies, !therapies.isEmpty {
                if let opt = options.first {
                    return m.isInEsaurimento(option: opt, recurrenceManager: rec)
                }
                // Fallback se non ci sono options: calcolo semplificato con soglia 7 giorni
                var totaleScorte: Double = 0
                var consumoGiornalieroTotale: Double = 0
                for t in therapies {
                    totaleScorte += Double(t.leftover())
                    consumoGiornalieroTotale += t.stimaConsumoGiornaliero(recurrenceManager: rec)
                }
                if totaleScorte <= 0 { return true }
                guard consumoGiornalieroTotale > 0 else { return false }
                let coverageDays = totaleScorte / consumoGiornalieroTotale
                return coverageDays < 7
            }
            // Se NON ha terapie: usa unità rimanenti
            if let r = remainingUnits(for: m) { return r < 7 }
            return false
        }

        var oggi: [Medicine] = []
        var watch: [Medicine] = []
        var ok: [Medicine] = []

        for m in medicines {
            // Oggi: rimangono dosi programmate per oggi non ancora assunte
            let scheduled = scheduledDosesTodayCount(for: m)
            let takenToday = intakeLogsTodayCount(for: m)
            if max(0, scheduled - takenToday) > 0 {
                oggi.append(m)
            } else if isWatch(m) {
                watch.append(m)
            } else {
                ok.append(m)
            }
        }

        // Ordinamento: 1) prossima assunzione (ASC) 2) stato scorte (rimanenti, ASC) 3) nome
        oggi.sort { (m1, m2) in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        watch.sort { (m1, m2) in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

        ok.sort { (m1, m2) in
            let d1 = nextOccurrence(for: m1) ?? Date.distantFuture
            let d2 = nextOccurrence(for: m2) ?? Date.distantFuture
            if d1 == d2 {
                let r1 = remainingUnits(for: m1) ?? Int.max
                let r2 = remainingUnits(for: m2) ?? Int.max
                if r1 == r2 {
                    return m1.nome.localizedCaseInsensitiveCompare(m2.nome) == .orderedAscending
                }
                return r1 < r2
            }
            return d1 < d2
        }

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
