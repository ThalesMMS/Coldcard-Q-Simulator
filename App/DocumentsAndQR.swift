import SwiftUI
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import VisionKit

extension UTType {
    static let psbt = UTType(exportedAs: "org.bitcoin.psbt", conformingTo: .data)
    static let coldcardSimulatorBackup = UTType(exportedAs: "dev.thales.coldcard-q-simulator-backup", conformingTo: .json)
    static let sevenZip = UTType(exportedAs: "org.7-zip.7-zip-archive", conformingTo: .data)
}

struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .json, .plainText, .psbt, .coldcardSimulatorBackup] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct QRCodeView: View {
    let payload: String
    var correctionLevel = "M"

    var body: some View {
        Group {
            if let image = makeImage() {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("QR code")
            } else {
                ContentUnavailableView("QR code too large", systemImage: "qrcode", description: Text("Export it as a file instead."))
            }
        }
    }

    private func makeImage() -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = correctionLevel
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Camera chrome from firmware `ux_q1.QRScannerInteraction.scan` / `scan_anything`.
@MainActor
private enum QRScannerChrome {
    static let anyQRPrompt = "Scan any QR code, or CANCEL"
    static let seedSecretPrompt = "Scan XPRV or Seed Words, or CANCEL"
    static let seedWordsPrompt = "Scan seed from a QR code"
    static let textPrompt = "Scan any QR or Barcode for text."
    static let messagePrompt = "Scan message from a QR code"

    static func prompt(for store: SimulatorStore) -> String {
        if store.pendingBagScan { return FirmwareCopy.scanBagBarcodePrompt }
        if store.pendingNoteQuickCreate { return textPrompt }
        switch store.screen {
        case .noteEditor, .passphrase:
            return textPrompt
        case .wordEntry, .importSeed:
            return seedWordsPrompt
        case .messageSigning:
            return messagePrompt
        default:
            break
        }
        if store.pendingEphemeral || store.currentMenu == .temporarySeed {
            return seedSecretPrompt
        }
        switch store.currentMenu {
        case .importExisting, .emptyWallet:
            return seedSecretPrompt
        default:
            return anyQRPrompt
        }
    }

    /// Firmware has no separate nav title; iOS uses the menu item name only when that is the scan entry.
    static func navigationTitle(for store: SimulatorStore) -> String {
        if store.pendingBagScan { return FirmwareCopy.scanBagBarcodePrompt }
        if store.pendingNoteQuickCreate { return "" }
        guard store.screen == .menu else { return "" }
        switch store.currentMenu {
        case .home: return "Scan Any QR Code"
        case .importExisting: return "Scan QR Code"
        case .temporarySeed: return "Import from QR Scan"
        default: return ""
        }
    }
}

struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: SimulatorStore
    let onScan: (String) -> ScanHandlingResult
    @State private var manualText = ""
    @State private var cameraError: String?
    @State private var scanStatus: String?

    private var prompt: String { QRScannerChrome.prompt(for: store) }
    private var title: String { QRScannerChrome.navigationTitle(for: store) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(includeLinearBarcodes: store.pendingBagScan) { value in
                        consume(value)
                    } onError: { message in
                        cameraError = message
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 4) {
                            Text(prompt)
                            if let progress = store.bbqrScanProgress, !progress.skipsProgressUI {
                                if !progress.partPattern.isEmpty {
                                    Text(progress.partPattern).font(.caption.monospaced())
                                }
                                Text(progress.instructionLine).fontWeight(.bold)
                                Text(progress.countLine)
                                    .foregroundStyle(.secondary)
                            } else if let scanStatus {
                                Text(scanStatus).fontWeight(.bold)
                            }
                        }
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                    }
                } else {
                    ContentUnavailableView("Scanner unavailable", systemImage: "qrcode.viewfinder",
                                           description: Text("Paste the content below or import a file."))
                }

                if let cameraError {
                    Text(cameraError).font(.footnote).foregroundStyle(.red)
                }

                TextEditor(text: $manualText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 100, maxHeight: 150)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35)))
                Button("Use pasted text") {
                    let value = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    consume(value)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("CANCEL") { dismiss() } } }
        }
    }

    private func consume(_ value: String) {
        switch onScan(value) {
        case .complete:
            dismiss()
        case .continueScanning(let message):
            scanStatus = message
            manualText = ""
        }
    }
}

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    var includeLinearBarcodes = false
    let onScan: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, onError: onError) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        var symbologies: [VNBarcodeSymbology] = [.qr]
        if includeLinearBarcodes {
            symbologies.append(contentsOf: [.code128, .code39, .code93, .ean8, .ean13, .itf14])
        }
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning else { return }
        do { try uiViewController.startScanning() }
        catch { onError(error.localizedDescription) }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let onError: (String) -> Void
        private var lastValue: String?
        private var lastDelivery = Date.distantPast

        init(onScan: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(updatedItems)
        }

        private func deliver(_ items: [RecognizedItem]) {
            for item in items {
                guard case .barcode(let barcode) = item, let value = barcode.payloadStringValue else { continue }
                let now = Date()
                if value == lastValue, now.timeIntervalSince(lastDelivery) < 1.0 { return }
                lastValue = value
                lastDelivery = now
                onScan(value)
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onError(String(describing: error))
        }
    }
}
