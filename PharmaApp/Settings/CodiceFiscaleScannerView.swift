import SwiftUI
import VisionKit

@available(iOS 16.0, *)
struct CodiceFiscaleScannerView: UIViewControllerRepresentable {
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    let onScan: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.code39])],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.attach(scanner)
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        if !uiViewController.isScanning {
            try? uiViewController.startScanning()
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: CodiceFiscaleScannerView
        private weak var scanner: DataScannerViewController?
        private var hasCaptured = false

        init(parent: CodiceFiscaleScannerView) {
            self.parent = parent
        }

        func attach(_ scanner: DataScannerViewController) {
            self.scanner = scanner
            if !scanner.isScanning {
                try? scanner.startScanning()
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(items: addedItems, scanner: dataScanner)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle(items: [item], scanner: dataScanner)
        }

        private func handle(items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !hasCaptured else { return }
            for item in items {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else {
                    continue
                }
                let normalized = CodiceFiscaleValidator.normalize(payload)
                guard CodiceFiscaleValidator.isValid(normalized) else { continue }
                hasCaptured = true
                parent.onScan(normalized)
                scanner.stopScanning()
                break
            }
        }
    }
}

@available(iOS 16.0, *)
struct CodiceFiscaleScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CodiceFiscaleScannerView { value in
                onScan(value)
                dismiss()
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 6)
            }
            .padding(16)
        }
        .ignoresSafeArea()
    }
}
