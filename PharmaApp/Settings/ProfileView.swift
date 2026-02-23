//
//  ProfileView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 05/02/26.
//

import SwiftUI
import CoreData
import MapKit
import CoreLocation
import CoreImage
struct ProfileView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    var showsDoneButton: Bool = true

    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>

    @AppStorage("preferredPharmacyName") private var preferredPharmacyName: String = ""

    @State private var selectedDoctor: Doctor?
    @State private var isDoctorDetailPresented = false
    @State private var selectedPerson: Person?
    @State private var isPersonDetailPresented = false
    @State private var fullscreenBarcodeCodiceFiscale: String?
    @State private var personPendingDeletion: Person?
    @State private var personDeleteErrorMessage: String?
    @State private var isPharmacyPickerPresented = false

    var body: some View {
        Form {
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

            // MARK: Dottori
            Section(header: HStack {
                Label("Dottori", systemImage: "stethoscope")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    Button {
                        selectedDoctor = doctor
                        isDoctorDetailPresented = true
                    } label: {
                        Text(doctor.nome ?? "Dottore")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: Farmacie
            Section(header: HStack {
                Label("Farmacie", systemImage: "cross.fill")
                Spacer()
                Button {
                    isPharmacyPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
            }) {
                if !preferredPharmacyName.isEmpty {
                    Text(preferredPharmacyName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                } else {
                    Text("Nessuna farmacia selezionata")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Messaggio ricetta
            Section(header: Label("Messaggio ricetta", systemImage: "text.bubble")) {
                NavigationLink {
                    PrescriptionMessageTemplateSettingsView()
                } label: {
                    Text("Template messaggio con placeholder {medico} e {medicinali}")
                }
            }

            // MARK: Settaggi terapia
            TherapySettingsSectionsView()
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
        .sheet(isPresented: $isPharmacyPickerPresented) {
            NavigationStack {
                PharmacyPickerView(selectedPharmacyName: $preferredPharmacyName)
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

// MARK: – Pharmacy Search ViewModel

final class PharmacySearchViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct PharmacyResult: Identifiable {
        let id = UUID()
        let name: String
        let address: String
        let distance: CLLocationDistance?
        let isOpen: Bool?
        let mapItem: MKMapItem
    }

    @Published var results: [PharmacyResult] = []
    @Published var isLoading = false

    private let locationManager = CLLocationManager()
    private var userLocation: CLLocation?
    private var currentSearch: MKLocalSearch?
    private var hasPerformedInitialSearch = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        userLocation = location
        if !hasPerformedInitialSearch {
            hasPerformedInitialSearch = true
            searchPharmacies(query: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func searchPharmacies(query: String?) {
        currentSearch?.cancel()

        let trimmed = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isCustomQuery = !trimmed.isEmpty

        if isCustomQuery {
            performSearch(query: trimmed, pinnedOpenItem: nil)
        } else {
            searchWithOpenFirst()
        }
    }

    private func searchWithOpenFirst() {
        isLoading = true

        let openRequest = makeSearchRequest(query: "farmacia aperta ora")
        let openSearch = MKLocalSearch(request: openRequest)
        currentSearch = openSearch

        openSearch.start { [weak self] openResponse, _ in
            guard let self else { return }
            let openItems = self.filterPharmacies(openResponse?.mapItems ?? [])
            let sortedOpen = self.sortByDistance(openItems)
            let pinnedOpen = sortedOpen.first

            self.performSearch(query: "farmacia", pinnedOpenItem: pinnedOpen)
        }
    }

    private func performSearch(query: String, pinnedOpenItem: MKMapItem?) {
        let request = makeSearchRequest(query: query)

        isLoading = true
        let search = MKLocalSearch(request: request)
        currentSearch = search

        search.start { [weak self] response, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLoading = false
                let items = self.filterPharmacies(response?.mapItems ?? [])
                let sorted = self.sortByDistance(items)
                self.results = self.buildResults(from: sorted, pinnedOpenItem: pinnedOpenItem)
            }
        }
    }

    private func makeSearchRequest(query: String) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])

        if let location = userLocation {
            request.region = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            )
            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }
        }
        return request
    }

    private func requestLocation() {
        if let cached = locationManager.location, cached.horizontalAccuracy >= 0 {
            userLocation = cached
            if !hasPerformedInitialSearch {
                hasPerformedInitialSearch = true
                searchPharmacies(query: nil)
            }
        }
        locationManager.requestLocation()
    }

    private func filterPharmacies(_ items: [MKMapItem]) -> [MKMapItem] {
        items.filter { item in
            if let category = item.pointOfInterestCategory, category != .pharmacy { return false }
            let name = (item.name ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
            let banned = ["erboristeria", "parafarmacia", "vitamine", "vitamin"]
            return !banned.contains(where: { name.contains($0) })
        }
    }

    private func sortByDistance(_ items: [MKMapItem]) -> [MKMapItem] {
        guard let location = userLocation else { return items }
        return items.sorted { lhs, rhs in
            let ld = lhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
            let rd = rhs.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude
            return ld < rd
        }
    }

    private func buildResults(from items: [MKMapItem], pinnedOpenItem: MKMapItem? = nil) -> [PharmacyResult] {
        var finalItems = items

        // Se c'e una farmacia aperta pinnata, mettila in cima e rimuovi duplicati
        if let pinned = pinnedOpenItem {
            finalItems.removeAll { ($0.name ?? "") == (pinned.name ?? "") }
            finalItems.insert(pinned, at: 0)
        }

        return finalItems.map { item -> PharmacyResult in
            let dist = userLocation.flatMap { item.placemark.location?.distance(from: $0) }
            let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality]
                .compactMap { $0 }
                .joined(separator: " ")
            let isPinned = pinnedOpenItem.map { ($0.name ?? "") == (item.name ?? "") } ?? false
            return PharmacyResult(
                name: item.name ?? "Farmacia",
                address: address,
                distance: dist,
                isOpen: isPinned ? true : nil,
                mapItem: item
            )
        }
    }

    func distanceText(for result: PharmacyResult) -> String? {
        guard let meters = result.distance else { return nil }
        if meters < 1000 {
            let rounded = Int((meters / 10).rounded()) * 10
            return "\(rounded) m"
        }
        let km = (meters / 1000 * 10).rounded() / 10
        return String(format: "%.1f km", km)
    }
}

// MARK: – Pharmacy Picker

struct PharmacyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedPharmacyName: String
    @StateObject private var searchVM = PharmacySearchViewModel()
    @State private var query = ""

    var body: some View {
        List {
            if searchVM.isLoading && searchVM.results.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Ricerca farmacie...")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(searchVM.results) { result in
                pharmacyRow(result)
            }
            if !searchVM.isLoading && searchVM.results.isEmpty {
                Section {
                    Text("Nessuna farmacia trovata")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca farmacia per nome")
        .onSubmit(of: .search) {
            searchVM.searchPharmacies(query: query)
        }
        .onChange(of: query) { newValue in
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchVM.searchPharmacies(query: nil)
            }
        }
        .navigationTitle("Seleziona farmacia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") {
                    dismiss()
                }
            }
        }
        .onAppear {
            searchVM.start()
        }
    }

    private func pharmacyRow(_ result: PharmacySearchViewModel.PharmacyResult) -> some View {
        Button {
            selectedPharmacyName = result.name
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if result.isOpen == true {
                            Text("Aperta")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green.opacity(0.18)))
                                .foregroundStyle(.green)
                        }
                    }
                    if !result.address.isEmpty {
                        Text(result.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let dist = searchVM.distanceText(for: result) {
                    Text(dist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if result.name == selectedPharmacyName {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: – Pharmacy Card

struct ProfilePharmacyCard: View {
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

struct FullscreenBarcodeView: View {
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

struct CodiceFiscaleBarcodeView: View {
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
