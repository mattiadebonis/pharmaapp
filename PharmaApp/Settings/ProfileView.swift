//
//  ProfileView.swift
//  PharmaApp
//
//  Created by Mattia De bonis on 05/02/26.
//

import SwiftUI
import CoreData
import MapKit

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    var showsDoneButton: Bool = true

    @FetchRequest(fetchRequest: Doctor.extractDoctors()) private var doctors: FetchedResults<Doctor>
    @FetchRequest(fetchRequest: Person.extractPersons()) private var persons: FetchedResults<Person>

    var body: some View {
        Form {
            Section(header: HStack {
                Text("Gestione Dottori")
                Spacer()
                NavigationLink(destination: AddDoctorView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(doctors) { doctor in
                    NavigationLink {
                        DoctorDetailView(doctor: doctor)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(doctor.nome ?? "")
                                .font(.headline)
                            if let mail = doctor.mail {
                                Text("Email: \(mail)")
                            }
                            if let telefono = doctor.telefono {
                                Text("Telefono: \(telefono)")
                            }
                        }
                    }
                }
            }

            Section("Farmacie") {
                ProfilePharmacyCard()
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section(header: HStack {
                Text("Gestione Persone")
                Spacer()
                NavigationLink(destination: AddPersonView()) {
                    Image(systemName: "plus")
                }
            }) {
                ForEach(persons) { person in
                    NavigationLink {
                        PersonDetailView(person: person)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(personDisplayName(for: person))
                                .font(.headline)
                            if person.is_account {
                                HStack(spacing: 6) {
                                    Text("Account")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if auth.user != nil {
                                        Text("Esci")
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(Color.red.opacity(0.12))
                                            )
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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
        .onAppear {
            AccountPersonService.shared.ensureAccountPerson(in: managedObjectContext)
            AccountPersonService.shared.syncAccountDisplayName(from: auth.user, in: managedObjectContext)
        }
        .onChange(of: auth.user) { user in
            AccountPersonService.shared.syncAccountDisplayName(from: user, in: managedObjectContext)
        }
    }

    private func personDisplayName(for person: Person) -> String {
        let first = (person.nome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (person.cognome ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let full = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Persona" : full
    }
}

private struct ProfilePharmacyCard: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var locationVM = LocationSearchViewModel()
    @State private var showCodiceFiscaleFullScreen = false
    @State private var codiceFiscaleEntries: [PrescriptionCFEntry] = []

    private let cardCornerRadius: CGFloat = 16
    private let pharmacyAccentColor = Color(red: 0.20, green: 0.62, blue: 0.36)

    private enum PharmacyRouteMode {
        case walking
        case driving

        var title: String {
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
        VStack(alignment: .leading, spacing: 12) {
            pharmacyHeader
            pharmacyMapPreview()
            HStack(spacing: 8) {
                routeButton(for: .walking)
                routeButton(for: .driving)
                codiceFiscaleButton
            }
            HStack(spacing: 8) {
                actionButton(
                    title: "Apri in Mappe",
                    systemImage: "map.fill",
                    enabled: canOpenMaps
                ) {
                    openDirections(.driving)
                }
                actionButton(
                    title: "Chiama",
                    systemImage: "phone.fill",
                    enabled: canCall
                ) {
                    locationVM.callPharmacy()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            locationVM.ensureStarted()
        }
        .fullScreenCover(isPresented: $showCodiceFiscaleFullScreen) {
            CodiceFiscaleFullscreenView(
                entries: codiceFiscaleEntries
            ) {
                showCodiceFiscaleFullScreen = false
            }
        }
    }

    private var pharmacyHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(locationVM.pinItem?.title ?? "Farmacia più vicina")
                    .font(.headline)
                    .lineLimit(2)
                if let line = pharmacyDetailsLine {
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("Attiva la posizione per vedere distanza, orari e contatti.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                VStack(spacing: 6) {
                    Image(systemName: "map")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Ricerca in corso della farmacia più vicina")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 150)
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
                Text(mode.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(routeMinutesText(for: mode))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.55)
    }

    private var codiceFiscaleButton: some View {
        Button {
            codiceFiscaleEntries = PrescriptionCodiceFiscaleResolver().entriesForRxAndLowStock(in: viewContext)
            showCodiceFiscaleFullScreen = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "creditcard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Codice fiscale")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Tessera")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(.blue)
        .disabled(!enabled)
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    private var canCall: Bool {
        let phone = locationVM.pinItem?.phone ?? locationVM.pinItem?.mapItem?.phoneNumber
        return phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var pharmacyDetailsLine: String? {
        var parts: [String] = []
        if let distance = pharmacyDistanceText() {
            parts.append("Distanza \(distance)")
        }
        if let slot = locationVM.todayOpeningText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !slot.isEmpty {
            parts.append("Orari oggi \(slot)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
        guard let minutes = routeMinutes(for: mode) else { return "Apri" }
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

#Preview {
    NavigationStack {
        ProfileView()
    }
    .environmentObject(AppViewModel())
    .environmentObject(AuthViewModel())
    .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
