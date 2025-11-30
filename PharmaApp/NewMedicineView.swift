import SwiftUI
import CoreData
import UIKit

struct NewMedicineView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appViewModel: AppViewModel
    var onAdded: (() -> Void)?
    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Option.extractOptions()) private var options: FetchedResults<Option>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>

    // Medicine fields (semplificati)
    @State private var nome: String = ""
    @State private var obbligoRicetta: Bool = false
    @State private var customThreshold: Int? = nil
    @State private var selectedDoctor: Doctor? = nil
    @State private var thresholdMode: ThresholdMode = .general
    @State private var thresholdValue: Int = 7
    @State private var therapySheetId = UUID()
    @State private var nameHighlights: [String] = []
    @State private var parsedName: String = ""
    @State private var recognizedChips: [String] = []

    // Unico campo confezione richiesto: numero unità per confezione
    @State private var numeroUnita: Int = 1
    @State private var tipologia: String = ""
    @State private var packageValore: Int32 = 0
    @State private var packageUnita: String = ""
    @State private var packageVolume: String = ""

    // Catalogo da medicinali.json
    @State private var selectedCatalogMedicine: CatalogMedicine? = nil
    @State private var selectedCatalogPackage: CatalogPackage? = nil

    // After creation open details
    @State private var showDetail: Bool = false
    @State private var createdMedicine: Medicine?
    @State private var createdPackage: Package?

    // Modal flags
    @State private var showRecipeSheet = false
    @State private var showThresholdSheet = false
    @State private var showTherapySheet = false
    
    @State private var draftContext: NSManagedObjectContext?
    @State private var draftMedicine: Medicine?
    @State private var draftPackage: Package?
    
    private enum ThresholdMode {
        case general, custom
    }
    
    private struct CatalogMedicine: Identifiable, Hashable {
        let id: String
        let name: String
        let principle: String
        let requiresPrescription: Bool
        let dosageDescription: String
        let packages: [CatalogPackage]
    }
    
    private struct CatalogPackage: Identifiable, Hashable {
        let id: String
        let label: String
        let units: Int
        let tipologia: String
        let dosageValue: Int32
        let dosageUnit: String
        let volume: String
        let requiresPrescription: Bool
    }
    
    init(prefill: CatalogSelection? = nil, onAdded: (() -> Void)? = nil) {
        self.onAdded = onAdded
        _nome = State(initialValue: prefill?.name ?? "")
        _obbligoRicetta = State(initialValue: prefill?.requiresPrescription ?? false)
        _numeroUnita = State(initialValue: prefill?.units ?? 1)
        _tipologia = State(initialValue: prefill?.tipologia ?? "")
        _packageValore = State(initialValue: prefill?.valore ?? 0)
        _packageUnita = State(initialValue: prefill?.unita ?? "")
        _packageVolume = State(initialValue: prefill?.volume ?? "")
        
        if let prefill {
            let pkg = CatalogPackage(
                id: prefill.id,
                label: prefill.packageLabel,
                units: prefill.units,
                tipologia: prefill.tipologia,
                dosageValue: prefill.valore,
                dosageUnit: prefill.unita,
                volume: prefill.volume,
                requiresPrescription: prefill.requiresPrescription
            )
            let med = CatalogMedicine(
                id: prefill.id,
                name: prefill.name,
                principle: prefill.principle,
                requiresPrescription: prefill.requiresPrescription,
                dosageDescription: prefill.packageLabel,
                packages: [pkg]
            )
            _selectedCatalogMedicine = State(initialValue: med)
            _selectedCatalogPackage = State(initialValue: pkg)
        } else {
            _selectedCatalogMedicine = State(initialValue: nil)
            _selectedCatalogPackage = State(initialValue: nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                
                Section(header: Text("Soglia scorte")) {
                    Toggle(isOn: Binding(
                        get: { customThreshold != nil },
                        set: { useCustom in
                            customThreshold = useCustom ? (customThreshold ?? generalThreshold) : nil
                            thresholdMode = useCustom ? .custom : .general
                            thresholdValue = customThreshold ?? generalThreshold
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Soglia personalizzata")
                            Text("Notifiche quando le scorte scendono sotto la soglia scelta.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .teal))
                    
                    if customThreshold != nil {
                        Stepper(value: Binding(
                            get: { customThreshold ?? generalThreshold },
                            set: { customThreshold = max(1, min($0, 60)); thresholdValue = customThreshold ?? generalThreshold }
                        ), in: 1...60) {
                            Text("Avvisami quando restano \(customThreshold ?? generalThreshold) giorni")
                        }
                    } else {
                        Text("Usa soglia generale: \(generalThreshold) giorni")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section(header: Text("Medico prescrittore")) {
                    Picker("Medico prescrittore", selection: Binding(
                        get: { selectedDoctor?.objectID },
                        set: { newID in
                            if let newID, let doc = doctors.first(where: { $0.objectID == newID }) {
                                selectedDoctor = doc
                            } else {
                                selectedDoctor = nil
                            }
                        }
                    )) {
                        Text("Nessuno").tag(NSManagedObjectID?.none)
                        ForEach(doctors, id: \.objectID) { doc in
                            Text(doctorFullName(doc)).tag(Optional(doc.objectID))
                        }
                    }
                }
                
                Section(header: Text("Terapie")) {
                    let therapies = (draftMedicine?.therapies as? Set<Therapy>) ?? []
                    if therapies.isEmpty {
                        Text("Nessuna terapia aggiunta.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(therapies), id: \.objectID) { therapy in
                            Text(therapy.rrule ?? "Terapia")
                        }
                    }
                    Button {
                        openTherapySheet()
                    } label: {
                        Label("Aggiungi terapia", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                Section {
                    Button {
                        createMedicine()
                    } label: {
                        Label("Aggiungi all'armadietto", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(CapsuleActionButtonStyle(fill: .teal, textColor: .white))
                    .disabled(!canCreate)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        
        .sheet(isPresented: $showDetail, onDismiss: { dismiss() }) {
            if let m = createdMedicine, let p = createdPackage {
                MedicineDetailView(medicine: m, package: p)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showRecipeSheet) {
            recipeSheet
        }
        .sheet(isPresented: $showThresholdSheet) {
            thresholdSheet
        }
        .sheet(isPresented: $showTherapySheet) {
            therapySheet.id(therapySheetId)
        }
    }

    
    private func optionButton(title: String, subtitle: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var doctorSubtitle: String? {
        guard let doc = selectedDoctor else { return "Nessuno" }
        let name = doctorFullName(doc)
        if let email = doc.mail?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
            return "\(name) • \(email)"
        }
        return name
    }
    
    private var thresholdSubtitle: String {
        if let custom = customThreshold {
            return "Personalizzata: \(custom) giorni"
        }
        return "Usa impostazioni generali (\(generalThreshold) giorni)"
    }
    
    private var ricettaSummary: String {
        if !obbligoRicetta {
            return "Ricetta non richiesta"
        }
        if let doc = selectedDoctor {
            return "Ricetta: \(doctorFullName(doc))"
        }
        return "Ricetta richiesta (medico non specificato)"
    }
    
    private var therapySubtitle: String {
        if let draftContext, let med = draftMedicine, let therapies = med.therapies, !therapies.isEmpty {
            return "Terapie aggiunte (\(therapies.count))"
        }
        return "Nessuna terapia aggiunta"
    }
    
    private var generalThreshold: Int {
        let value = Int(options.first?.day_threeshold_stocks_alarm ?? 0)
        return value > 0 ? value : 7
    }
    
    private var ricettaSubtitle: String {
        if !obbligoRicetta {
            return "Non richiesta"
        }
        if let doc = selectedDoctor {
            return "Richiesta da \(doctorFullName(doc))"
        }
        return "Richiesta (medico non specificato)"
    }
    
    private func doctorFullName(_ doctor: Doctor) -> String {
        let first = (doctor.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (doctor.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = [first, last].filter { !$0.isEmpty }
        return comps.isEmpty ? "Medico" : comps.joined(separator: " ")
    }
    
    private var recipeSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Stato ricetta")) {
                    Toggle("Richiede ricetta medica", isOn: Binding(
                        get: { obbligoRicetta },
                        set: { newValue in
                            obbligoRicetta = newValue
                            if !newValue {
                                selectedDoctor = nil
                            }
                        }
                    ))
                    .toggleStyle(SwitchToggleStyle(tint: .teal))
                    Text("Se è attivo, il farmaco viene considerato con ricetta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Section(header: Text("Medico prescrittore")) {
                    if !obbligoRicetta {
                        Text("Se scegli un medico, la ricetta verrà segnata come necessaria.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        selectedDoctor = nil
                        obbligoRicetta = obbligoRicetta // no change
                    } label: {
                        HStack {
                            Text("Nessuno")
                            Spacer()
                            if selectedDoctor == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(doctors, id: \.objectID) { doctor in
                        Button {
                            selectedDoctor = doctor
                            obbligoRicetta = true
                        } label: {
                            HStack {
                                Text(doctorFullName(doctor))
                                Spacer()
                                if selectedDoctor?.objectID == doctor.objectID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ricetta medica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { showRecipeSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { showRecipeSheet = false }
                }
            }
        }
    }
    
    private var thresholdSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Modalità soglia")) {
                    Button {
                        thresholdMode = .general
                        thresholdValue = generalThreshold
                    } label: {
                        HStack {
                            Image(systemName: thresholdMode == .general ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Usa la soglia generale (\(generalThreshold) giorni)")
                                Text("Valida per tutti i farmaci senza impostazioni personalizzate.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        thresholdMode = .custom
                        if customThreshold == nil { thresholdValue = generalThreshold }
                    } label: {
                        HStack {
                            Image(systemName: thresholdMode == .custom ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Imposta una soglia solo per questo farmaco")
                                if thresholdMode == .custom {
                                    Text("Soglia attuale: \(thresholdValue) giorni")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if thresholdMode == .custom {
                        Stepper(value: Binding(
                            get: { thresholdValue },
                            set: { thresholdValue = max(1, min($0, 60)) }
                        ), in: 1...60) {
                            Text("Avvisami quando restano \(thresholdValue) giorni")
                        }
                    }
                }
            }
            .navigationTitle("Soglia scorte")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                thresholdMode = customThreshold == nil ? .general : .custom
                thresholdValue = customThreshold ?? generalThreshold
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { showThresholdSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        if thresholdMode == .general {
                            customThreshold = nil
                        } else {
                            customThreshold = thresholdValue
                        }
                        showThresholdSheet = false
                    }
                }
            }
        }
    }
    
    private var therapySheet: some View {
        NavigationStack {
            if let draftMedicine, let draftPackage, let draftContext {
                TherapyFormView(
                    medicine: draftMedicine,
                    package: draftPackage,
                    context: draftContext
                )
                .environment(\.managedObjectContext, draftContext)
                .environmentObject(appViewModel)
                .id(therapySheetId)
            } else {
                VStack(spacing: 12) {
                    Text("Crea il farmaco per aggiungere una terapia.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Button("Chiudi") { showTherapySheet = false }
                        .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }
    
    private var canCreate: Bool {
        return selectedCatalogPackage != nil
    }

    private var navTitle: String {
        guard let med = selectedCatalogMedicine, let pkg = selectedCatalogPackage else {
            return "Nuovo farmaco"
        }
        let unitPart: String
        if packageValore > 0 {
            unitPart = "\(packageValore)\(packageUnita.isEmpty ? "" : " \(packageUnita)")"
        } else {
            unitPart = ""
        }
        let qtyPart = numeroUnita > 0 ? "\(numeroUnita) pz" : ""
        let pieces = [med.name, unitPart, qtyPart].filter { !$0.isEmpty }
        return pieces.joined(separator: " • ")
    }

    private func baseName() -> String {
        if let catalogName = selectedCatalogMedicine?.name {
            return catalogName
        }
        let source = parsedName.isEmpty ? nome : parsedName
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Medicinale" : trimmed
    }

    private func ensureParentMedicineAndPackage() -> (Medicine, Package) {
        if let med = createdMedicine, let pkg = createdPackage {
            med.nome = baseName()
            med.obbligo_ricetta = obbligoRicetta
            med.principio_attivo = selectedCatalogMedicine?.principle ?? med.principio_attivo
            med.custom_stock_threshold = Int32(customThreshold ?? 0)
            med.prescribingDoctor = selectedDoctor
            pkg.numero = Int32(numeroUnita)
            pkg.tipologia = tipologia
            pkg.valore = packageValore
            pkg.unita = packageUnita
            pkg.volume = packageVolume
            return (med, pkg)
        }
        let medicine = Medicine(context: context)
        medicine.id = UUID()
        medicine.nome = baseName()
        medicine.principio_attivo = selectedCatalogMedicine?.principle ?? ""
        medicine.obbligo_ricetta = obbligoRicetta
        medicine.in_cabinet = true
        medicine.custom_stock_threshold = Int32(customThreshold ?? 0)
        medicine.prescribingDoctor = selectedDoctor

        let package = Package(context: context)
        package.id = UUID()
        package.tipologia = tipologia
        package.unita = packageUnita
        package.volume = packageVolume
        package.valore = packageValore
        package.numero = Int32(numeroUnita)
        package.medicine = medicine
        medicine.addToPackages(package)
        createdMedicine = medicine
        createdPackage = package
        return (medicine, package)
    }

    private func buildDraftContextIfNeeded() {
        if draftContext != nil { return }
        let child = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        child.parent = context
        let medicine = Medicine(context: child)
        medicine.id = UUID()
        medicine.nome = baseName()
        medicine.principio_attivo = selectedCatalogMedicine?.principle ?? ""
        medicine.obbligo_ricetta = obbligoRicetta
        medicine.in_cabinet = true
        medicine.custom_stock_threshold = Int32(customThreshold ?? 0)
        if let doc = selectedDoctor {
            medicine.prescribingDoctor = child.object(with: doc.objectID) as? Doctor
        }
        let package = Package(context: child)
        package.id = UUID()
        package.tipologia = tipologia
        package.unita = packageUnita
        package.volume = packageVolume
        package.valore = packageValore
        package.numero = Int32(numeroUnita)
        package.medicine = medicine
        medicine.addToPackages(package)
        draftContext = child
        draftMedicine = medicine
        draftPackage = package
    }

    private func syncDraftWithCurrentFields() {
        guard let child = draftContext, let med = draftMedicine, let pkg = draftPackage else { return }
        med.nome = baseName()
        med.obbligo_ricetta = obbligoRicetta
        med.custom_stock_threshold = Int32(customThreshold ?? 0)
        if let doc = selectedDoctor {
            med.prescribingDoctor = child.object(with: doc.objectID) as? Doctor
        } else {
            med.prescribingDoctor = nil
        }
        pkg.numero = Int32(numeroUnita)
        pkg.tipologia = tipologia
        pkg.valore = packageValore
        pkg.unita = packageUnita
        pkg.volume = packageVolume
    }

    private func createMedicine() {
        let _ = ensureParentMedicineAndPackage()
        syncDraftWithCurrentFields()
        do {
            if let child = draftContext, child.hasChanges {
                try child.save()
                if let draftMed = draftMedicine {
                    let medParent = try? context.existingObject(with: draftMed.objectID) as? Medicine
                    if let medParent {
                        createdMedicine = medParent
                    }
                }
                if let draftPkg = draftPackage {
                    let pkgParent = try? context.existingObject(with: draftPkg.objectID) as? Package
                    if let pkgParent {
                        createdPackage = pkgParent
                    }
                }
            }
            try context.save()
            onAdded?()
            dismiss()
        } catch {
            print("Errore salvataggio medicinale o terapie: \(error)")
        }
    }

    private func openTherapySheet() {
        buildDraftContextIfNeeded()
        syncDraftWithCurrentFields()
        therapySheetId = UUID()
        showTherapySheet = true
    }
    
    
    private func applyTherapyDraft(_ draft: TherapyDraft) {
        buildDraftContextIfNeeded()
        syncDraftWithCurrentFields()
        guard let child = draftContext, let med = draftMedicine, let pkg = draftPackage else { return }
        
        // reset terapie esistenti nel draft
        if let existing = med.therapies as? Set<Therapy> {
            for t in existing {
                child.delete(t)
            }
        }
        
        let therapy = Therapy(context: child)
        therapy.id = UUID()
        therapy.medicine = med
        therapy.package = pkg
        therapy.start_date = Date()
        therapy.importance = Therapy.importanceValues.last
        let parentPerson = draft.person ?? persons.first
        if let parentPerson,
           let childPerson = child.object(with: parentPerson.objectID) as? Person {
            therapy.person = childPerson
        } else {
            therapy.person = createPlaceholderPerson(in: child)
        }
        therapy.rrule = "FREQ=DAILY;INTERVAL=1"
        
        for time in (draft.times.isEmpty ? [defaultTime()] : draft.times) {
            let dose = Dose(context: child)
            dose.id = UUID()
            dose.time = normalizedToday(time)
            dose.therapy = therapy
        }
    }
    
    private func createPlaceholderPerson(in context: NSManagedObjectContext) -> Person {
        let person = Person(context: context)
        person.id = UUID()
        person.nome = "Persona"
        person.cognome = ""
        return person
    }
    
    private func normalizedToday(_ time: Date) -> Date {
        var comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let today = Calendar.current.startOfDay(for: Date())
        comps.year = Calendar.current.component(.year, from: today)
        comps.month = Calendar.current.component(.month, from: today)
        comps.day = Calendar.current.component(.day, from: today)
        return Calendar.current.date(from: comps) ?? time
    }
    
    private func defaultTime() -> Date {
        var comps = DateComponents()
        comps.hour = 8
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}
