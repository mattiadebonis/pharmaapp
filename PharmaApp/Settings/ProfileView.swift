//
//  ProfileView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 05/02/26.
//

import SwiftUI
import CoreData
import MapKit
import CoreImage
struct ProfileView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    var showsDoneButton: Bool = true

    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>

    @State private var selectedDoctor: Doctor?
    @State private var isDoctorDetailPresented = false
    @State private var selectedPerson: Person?
    @State private var isPersonDetailPresented = false
    @State private var fullscreenBarcodeCodiceFiscale: String?
    @State private var personPendingDeletion: Person?
    @State private var personDeleteErrorMessage: String?

    var body: some View {
        Form {
            // MARK: Farmacie
            Section(header: Label("Farmacie", systemImage: "cross.case.fill")) {
                ProfilePharmacyCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // MARK: Dottori
            Section(header: HStack {
                Label("Dottori", systemImage: "stethoscope")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            selectedDoctor = doctor
                            isDoctorDetailPresented = true
                        } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(doctor.nome ?? "")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    if let status = doctorStatusText(for: doctor) {
                                        Text(status)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)

                        if hasDoctorContacts(doctor) {
                            HStack(spacing: 8) {
                                if let mail = doctor.mail, !mail.isEmpty {
                                    doctorContactButton(
                                        icon: "envelope.fill",
                                        label: "Email",
                                        color: .blue
                                    ) { openEmail(mail) }
                                }
                                if let phone = doctor.telefono, !phone.isEmpty {
                                    doctorContactButton(
                                        icon: "phone.fill",
                                        label: "Chiama",
                                        color: .green
                                    ) { callPhone(phone) }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: Persone
            Section(header: HStack {
                Label("Persone", systemImage: "person.2.fill")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(persons) { person in
                    HStack(spacing: 0) {
                        Button {
                            selectedPerson = person
                            isPersonDetailPresented = true
                        } label: {
                            Text(personDisplayName(for: person))
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if let cf = person.codice_fiscale, !cf.isEmpty {
                            Button {
                                fullscreenBarcodeCodiceFiscale = cf
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "creditcard.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.blue)
                                    Text("Tessera sanitaria")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !person.is_account {
                            Button(role: .destructive) {
                                personPendingDeletion = person
                            } label: {
                                Text("Elimina")
                            }
                        }

                        if person.is_account, auth.user != nil {
                            Button(role: .destructive) {
                                auth.signOut()
                                if showsDoneButton {
                                    dismiss()
                                }
                            } label: {
                                Text("Esci")
                            }
                        }
                    }
                }
            }

            // MARK: Settaggi terapia
            TherapySettingsSectionsView()

            Section(header: Label("Messaggio ricetta", systemImage: "text.bubble")) {
                NavigationLink {
                    PrescriptionMessageTemplateSettingsView()
                } label: {
                    Text("Template messaggio con placeholder {medico} e {medicinali}")
                }
            }
        }
        .navigationTitle("Profilo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        dismiss()
                    }
                }
            }
        }
        .navigationDestination(isPresented: $isDoctorDetailPresented) {
            if let doctor = selectedDoctor {
                DoctorDetailView(doctor: doctor)
            }
        }
        .navigationDestination(isPresented: $isPersonDetailPresented) {
            if let person = selectedPerson {
                PersonDetailView(person: person)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { fullscreenBarcodeCodiceFiscale != nil },
            set: { if !$0 { fullscreenBarcodeCodiceFiscale = nil } }
        )) {
            if let cf = fullscreenBarcodeCodiceFiscale {
                FullscreenBarcodeView(codiceFiscale: cf) {
                    fullscreenBarcodeCodiceFiscale = nil
                }
            }
        }
        .onAppear {
            AccountPersonService.shared.ensureAccountPerson(in: managedObjectContext)
            AccountPersonService.shared.syncAccountDisplayName(from: auth.user, in: managedObjectContext)
        }
        .onChange(of: auth.user) { user in
            AccountPersonService.shared.syncAccountDisplayName(from: user, in: managedObjectContext)
        }
        .alert(
            "Eliminare questa persona?",
            isPresented: Binding(
                get: { personPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        personPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("Elimina", role: .destructive) {
                if let person = personPendingDeletion {
                    deletePerson(person)
                }
                personPendingDeletion = nil
            }
            Button("Annulla", role: .cancel) {
                personPendingDeletion = nil
            }
        } message: {
            Text("Le terapie associate verranno assegnate all'account.")
        }
        .alert("Errore", isPresented: Binding(
            get: { personDeleteErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    personDeleteErrorMessage = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(personDeleteErrorMessage ?? "Errore sconosciuto.")
        }
    }

    // MARK: – Doctor helpers

    private func hasDoctorContacts(_ doctor: Doctor) -> Bool {
        let mail = doctor.mail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let phone = doctor.telefono?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !mail.isEmpty || !phone.isEmpty
    }

    private func doctorContactButton(
        icon: String,
        label: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(color.opacity(0.12)))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func openEmail(_ address: String) {
        if let url = URL(string: "mailto:\(address)") {
            UIApplication.shared.open(url)
        }
    }

    private func callPhone(_ number: String) {
        let cleaned = number.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(cleaned)") {
            UIApplication.shared.open(url)
        }
    }

    // MARK: – Doctor schedule helpers

    private func doctorStatusText(for doctor: Doctor) -> String? {
        let schedule = doctor.scheduleDTO
        let now = Date()
        let calendar = Calendar.current
        let weekdayOrder: [DoctorScheduleDTO.DaySchedule.Weekday] = [
            .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
        ]
        let calWeekday = calendar.component(.weekday, from: now)
        let todayEnum = weekdayOrder[calWeekday - 1]
        guard let todaySchedule = schedule.days.first(where: { $0.day == todayEnum }) else {
            return nil
        }
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute

        func parseMinutes(_ s: String) -> Int? {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] * 60 + parts[1]
        }
        func fmt(_ minutes: Int) -> String {
            String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }

        switch todaySchedule.mode {
        case .closed:
            return doctorNextOpeningText(schedule: schedule, after: todayEnum, weekdayOrder: weekdayOrder)
        case .continuous:
            guard let start = parseMinutes(todaySchedule.primary.start),
                  let end = parseMinutes(todaySchedule.primary.end) else { return nil }
            if nowMinutes >= start && nowMinutes < end {
                return "Aperto fino alle \(fmt(end))"
            } else if nowMinutes < start {
                return "Apre alle \(fmt(start))"
            } else {
                return doctorNextOpeningText(schedule: schedule, after: todayEnum, weekdayOrder: weekdayOrder)
            }
        case .split:
            guard let s1 = parseMinutes(todaySchedule.primary.start),
                  let e1 = parseMinutes(todaySchedule.primary.end),
                  let s2 = parseMinutes(todaySchedule.secondary.start),
                  let e2 = parseMinutes(todaySchedule.secondary.end) else { return nil }
            if nowMinutes >= s1 && nowMinutes < e1 {
                return "Aperto fino alle \(fmt(e1))"
            } else if nowMinutes >= s2 && nowMinutes < e2 {
                return "Aperto fino alle \(fmt(e2))"
            } else if nowMinutes < s1 {
                return "Apre alle \(fmt(s1))"
            } else if nowMinutes < s2 {
                return "Apre alle \(fmt(s2))"
            } else {
                return doctorNextOpeningText(schedule: schedule, after: todayEnum, weekdayOrder: weekdayOrder)
            }
        }
    }

    private func doctorNextOpeningText(
        schedule: DoctorScheduleDTO,
        after day: DoctorScheduleDTO.DaySchedule.Weekday,
        weekdayOrder: [DoctorScheduleDTO.DaySchedule.Weekday]
    ) -> String {
        guard let currentIdx = weekdayOrder.firstIndex(of: day) else { return "Chiuso" }
        for offset in 1...7 {
            let nextIdx = (currentIdx + offset) % 7
            let nextDay = weekdayOrder[nextIdx]
            guard let nextSchedule = schedule.days.first(where: { $0.day == nextDay }),
                  nextSchedule.mode != .closed else { continue }
            let openTime: String
            switch nextSchedule.mode {
            case .continuous: openTime = nextSchedule.primary.start
            case .split:      openTime = nextSchedule.primary.start
            case .closed:     continue
            }
            if offset == 1 { return "Chiuso · domani alle \(openTime)" }
            return "Chiuso · \(nextSchedule.day.displayName) alle \(openTime)"
        }
        return "Chiuso"
    }

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }

    private func deletePerson(_ person: Person) {
        let context = person.managedObjectContext ?? managedObjectContext
        do {
            try PersonDeletionService.shared.delete(person, in: context)
            if selectedPerson?.objectID == person.objectID {
                selectedPerson = nil
                isPersonDetailPresented = false
            }
        } catch {
            context.rollback()
            personDeleteErrorMessage = error.localizedDescription
            print("Errore nell'eliminazione della persona: \(error.localizedDescription)")
        }
    }
}

// MARK: – Pharmacy Card

private struct ProfilePharmacyCard: View {
    @StateObject private var locationVM = LocationSearchViewModel()

    private let cardCornerRadius: CGFloat = 16
    private let pharmacyAccentColor = Color(red: 0.20, green: 0.62, blue: 0.36)

    private enum PharmacyRouteMode {
        case walking
        case driving

        var accessibilityLabel: String {
            switch self {
            case .walking: return "A piedi"
            case .driving: return "In auto"
            }
        }

        var systemImage: String {
            switch self {
            case .walking: return "figure.walk"
            case .driving: return "car.fill"
            }
        }

        var launchOption: String {
            switch self {
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            pharmacyHeader
            pharmacyMapPreview()
            HStack(spacing: 8) {
                routeButton(for: .walking)
                routeButton(for: .driving)
                callRouteButton()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            locationVM.ensureStarted()
        }
    }

    private var pharmacyHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(locationVM.pinItem?.title ?? "Farmacia più vicina")
                    .font(.headline)
                    .lineLimit(2)
                if locationVM.pinItem == nil {
                    Text("Attiva la posizione per vedere distanza, orari e contatti.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Distanza \(pharmacyDistanceText() ?? "non disponibile")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let statusText = pharmacyStatusText {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(pharmacyStatusFillColor)
                    )
                    .foregroundStyle(pharmacyStatusTextColor)
            }
        }
    }

    @ViewBuilder
    private func pharmacyMapPreview() -> some View {
        if let region = locationVM.region {
            ZStack {
                Map(coordinateRegion: Binding(
                    get: { locationVM.region ?? region },
                    set: { locationVM.region = $0 }
                ))
                .allowsHitTesting(false)

                if locationVM.pinItem != nil {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.red)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                openDirections(.driving)
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Attiva la posizione per vedere la mappa")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
            }
            .frame(height: 140)
        }
    }

    private func routeButton(for mode: PharmacyRouteMode) -> some View {
        Button {
            openDirections(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(routeMinutesText(for: mode))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.45)
        .accessibilityLabel(mode.accessibilityLabel)
    }

    private func callRouteButton() -> some View {
        Button {
            locationVM.callPharmacy()
        } label: {
            Image(systemName: "phone.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.green)
                )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!canCall)
        .opacity(canCall ? 1 : 0.45)
        .accessibilityLabel("Chiama farmacia")
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    private var canCall: Bool {
        let phone = locationVM.pinItem?.phone ?? locationVM.pinItem?.mapItem?.phoneNumber
        return phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var pharmacyStatusText: String? {
        guard locationVM.pinItem != nil else { return nil }
        if locationVM.isLikelyOpen == true {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == false {
            return "Chiusa"
        }
        return nil
    }

    private var pharmacyStatusTextColor: Color {
        pharmacyStatusText == "Aperta" ? pharmacyAccentColor : .secondary
    }

    private var pharmacyStatusFillColor: Color {
        pharmacyStatusText == "Aperta"
            ? pharmacyAccentColor.opacity(0.18)
            : Color.secondary.opacity(0.18)
    }

    private func routeMinutesText(for mode: PharmacyRouteMode) -> String {
        guard let minutes = routeMinutes(for: mode) else { return "–" }
        return "\(minutes) min"
    }

    private func routeMinutes(for mode: PharmacyRouteMode) -> Int? {
        guard let distance = locationVM.distanceMeters else { return nil }
        switch mode {
        case .walking:
            if let exactMinutes = locationVM.walkingRouteMinutes {
                return exactMinutes
            }
            return max(1, Int(round(distance / 83.0)))
        case .driving:
            if let exactMinutes = locationVM.drivingRouteMinutes {
                return exactMinutes
            }
            return max(1, Int(round(distance / 750.0)))
        }
    }

    private func pharmacyDistanceText() -> String? {
        guard let meters = locationVM.distanceMeters else { return nil }
        if meters < 1000 {
            let roundedMeters = Int((meters / 10).rounded()) * 10
            return "\(roundedMeters) m"
        }
        let km = meters / 1000
        let roundedKm = (km * 10).rounded() / 10
        return String(format: "%.1f km", roundedKm)
    }

    private func openDirections(_ mode: PharmacyRouteMode) {
        guard let item = pharmacyMapItem() else {
            locationVM.ensureStarted()
            return
        }
        let launchOptions = [MKLaunchOptionsDirectionsModeKey: mode.launchOption]
        MKMapItem.openMaps(with: [MKMapItem.forCurrentLocation(), item], launchOptions: launchOptions)
    }

    private func pharmacyMapItem() -> MKMapItem? {
        guard let pin = locationVM.pinItem else { return nil }
        if let item = pin.mapItem {
            return item
        }
        let placemark = MKPlacemark(coordinate: pin.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = pin.title
        return item
    }
}

// MARK: – Fullscreen Barcode

private struct FullscreenBarcodeView: View {
    let codiceFiscale: String
    let onClose: () -> Void
    @State private var barcodeImage: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                if let image = barcodeImage {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(.horizontal, 24)
                } else {
                    ProgressView()
                }

                Text(codiceFiscale)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(.black)

                Spacer()
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.gray)
            }
            .padding(16)
        }
        .task {
            barcodeImage = await Task.detached(priority: .userInitiated) {
                generateBarcode(from: codiceFiscale)
            }.value
        }
    }

    private func generateBarcode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(7.0, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: – Barcode view

private struct CodiceFiscaleBarcodeView: View {
    let codiceFiscale: String
    @State private var barcodeImage: UIImage?

    var body: some View {
        Group {
            if let image = barcodeImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Barcode codice fiscale \(codiceFiscale)")
            } else {
                Color.clear.frame(height: 36)
            }
        }
        .task(id: codiceFiscale) {
            guard barcodeImage == nil else { return }
            barcodeImage = await Task.detached(priority: .userInitiated) {
                generateBarcode(from: codiceFiscale)
            }.value
        }
    }

    private func generateBarcode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CICode128BarcodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(7.0, forKey: "inputQuietSpace")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AppViewModel())
    .environmentObject(AuthViewModel())
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
