import SwiftUI
import MapKit
import Code39

struct PharmacyCardsView: View {
    @EnvironmentObject private var codiceFiscaleStore: CodiceFiscaleStore
    @StateObject private var locationVM = LocationSearchViewModel()
    @State private var showCodiceFiscaleFullScreen = false

    private let pharmacyCardCornerRadius: CGFloat = 16
    private let pharmacyAccentColor = Color(red: 0.20, green: 0.62, blue: 0.36)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                pharmacySuggestionCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .fullScreenCover(isPresented: $showCodiceFiscaleFullScreen) {
            codiceFiscaleFullScreen()
        }
        .navigationTitle("Farmacia")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            locationVM.ensureStarted()
        }
    }

    // MARK: - Pharmacy card
    @ViewBuilder
    private func pharmacySuggestionCard() -> some View {
        let isClosed = locationVM.isLikelyOpen == false
        VStack(alignment: .leading, spacing: 6) {
            if locationVM.pinItem != nil {
                pharmacyMapHeader()
            }
            if !isClosed {
                pharmacyRouteButtons(
                    distanceLine: pharmacyDistanceText(),
                    statusLine: nil
                )
            } else {
                Text("Riprova più tardi o spostati di qualche centinaio di metri.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
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
            .clipShape(RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: pharmacyCardCornerRadius, style: .continuous)
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

    @ViewBuilder
    private func pharmacyMapHeader() -> some View {
        if let pin = locationVM.pinItem {
            let statusLine = pharmacyStatusText()
            HStack(spacing: 6) {
                Text(pin.title)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let statusLine {
                    Text("·")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    Text(statusLine)
                        .font(.system(size: 17, weight: statusLine == "Aperta" ? .semibold : .regular))
                        .foregroundColor(statusLine == "Aperta" ? pharmacyAccentColor : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func pharmacyRouteButtons(distanceLine: String?, statusLine: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if distanceLine != nil || statusLine != nil {
                HStack(spacing: 10) {
                    if let distanceLine {
                        Text("Distanza \(distanceLine)")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                    if let statusLine {
                        Text(statusLine)
                            .font(.system(size: 17, weight: statusLine == "Aperta" ? .semibold : .regular))
                            .foregroundColor(statusLine == "Aperta" ? pharmacyAccentColor : .secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                pharmacyRouteButton(for: .walking)
                pharmacyRouteButton(for: .driving)
                pharmacyCodiceFiscaleButton()
            }
        }
    }

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

    private func pharmacyRouteButton(for mode: PharmacyRouteMode) -> some View {
        let minutesText = pharmacyRouteMinutesText(for: mode)
        return Button {
            openDirections(mode)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(minutesText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canOpenMaps)
        .opacity(canOpenMaps ? 1 : 0.55)
    }

    private func pharmacyCodiceFiscaleButton() -> some View {
        Button {
            showCodiceFiscaleFullScreen = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "creditcard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text("Codice fiscale")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.blue)
            )
        }
        .buttonStyle(.plain)
    }

    private var canOpenMaps: Bool {
        locationVM.pinItem != nil
    }

    private func pharmacyRouteMinutesText(for mode: PharmacyRouteMode) -> String {
        guard let minutes = pharmacyRouteMinutes(for: mode) else {
            return "Attiva la posizione"
        }
        return "\(minutes) min"
    }

    private func pharmacyRouteMinutes(for mode: PharmacyRouteMode) -> Int? {
        guard let distance = locationVM.distanceMeters else { return nil }
        switch mode {
        case .walking:
            return max(1, Int(round(distance / 83.0)))
        case .driving:
            return max(1, Int(round(distance / 750.0)))
        }
    }

    private func openDirections(_ mode: PharmacyRouteMode) {
        guard let item = pharmacyMapItem() else { return }
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

    private func pharmacyStatusText() -> String? {
        guard locationVM.pinItem != nil else { return nil }
        if locationVM.isLikelyOpen == false {
            return nil
        }
        if locationVM.closingTimeText != nil {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == true {
            return "Aperta"
        }
        if locationVM.isLikelyOpen == nil && locationVM.todayOpeningText == nil {
            return nil
        }
        if let slot = locationVM.todayOpeningText {
            let now = Date()
            if OpeningHoursParser.activeInterval(from: slot, now: now) != nil {
                return "Aperta"
            }
        }
        return "Chiuso"
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

    // MARK: - Codice fiscale
    @ViewBuilder
    private func codiceFiscaleCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let codice = codiceFiscaleStore.codiceFiscale?.trimmingCharacters(in: .whitespacesAndNewlines),
               !codice.isEmpty {
                let displayCodice = codiceFiscaleDisplayText(codice)
                VStack(spacing: 8) {
                    Code39View(displayCodice)
                        .frame(maxWidth: .infinity)
                        .frame(height: 70)
                        .accessibilityLabel("Barcode Codice Fiscale")
                        .accessibilityValue(displayCodice)
                    Text(displayCodice)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Aggiungi il codice fiscale dal profilo.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(16)
        .contentShape(Rectangle())
        .onTapGesture {
            showCodiceFiscaleFullScreen = true
        }
    }

    private func codiceFiscaleDisplayText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        return trimmed.uppercased()
    }

    private func codiceFiscaleFullScreen() -> some View {
        ZStack(alignment: .topTrailing) {
            Color.white
                .ignoresSafeArea()
            GeometryReader { proxy in
                ZStack {
                    if let codice = codiceFiscaleStore.codiceFiscale {
                        let displayCodice = codiceFiscaleDisplayText(codice)
                        VStack(spacing: 12) {
                            Code39View(displayCodice)
                                .frame(maxWidth: min(proxy.size.width * 0.92, 700))
                                .frame(height: 140)
                                .accessibilityLabel("Barcode Codice Fiscale")
                                .accessibilityValue(displayCodice)
                            Text(displayCodice)
                                .font(.system(.callout, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Aggiungi il codice fiscale dal profilo.")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button {
                showCodiceFiscaleFullScreen = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.35))
                    )
            }
            .padding(20)
        }
    }
}

#Preview {
    NavigationStack {
        PharmacyCardsView()
    }
    .environmentObject(CodiceFiscaleStore())
}
