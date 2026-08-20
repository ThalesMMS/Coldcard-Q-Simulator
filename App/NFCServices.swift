import Foundation
import SwiftUI
#if canImport(CoreNFC)
import CoreNFC
#endif

/// Foreground Core NFC NDEF read/write. Tag emulation / HCE is out of scope.
enum SimulatorNFCError: LocalizedError {
    case unavailable
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "NFC NDEF is not available. Use Files or paste as the simulator stand-in."
        case .cancelled: "NFC cancelled."
        case .failed(let message): message
        }
    }
}

final class SimulatorNFCWriter {
    static let shared = SimulatorNFCWriter()

    func shareText(_ text: String, completion: @escaping (Result<Void, Error>) -> Void) {
        SimulatorNFC.write(.text(text), prompt: "Tap phone to screen, or CANCEL.", completion: completion)
    }
}

enum SimulatorNFC {
    static var isAvailable: Bool {
        #if canImport(CoreNFC)
        NFCNDEFReaderSession.readingAvailable
        #else
        false
        #endif
    }

    static func read(prompt: String = "Hold near an NDEF tag",
                     completion: @escaping (Result<[Data], Error>) -> Void) {
        #if canImport(CoreNFC)
        NFCSessionController.shared.read(prompt: prompt, completion: completion)
        #else
        completion(.failure(SimulatorNFCError.unavailable))
        #endif
    }

    static func write(_ message: SimulatorNDEFMessage,
                      prompt: String = "Hold near a writable NDEF tag",
                      completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(CoreNFC)
        NFCSessionController.shared.write(message, prompt: prompt, completion: completion)
        #else
        completion(.failure(SimulatorNFCError.unavailable))
        #endif
    }
}

/// Firmware `NFC.start_psbt_rx()` over Core NFC NDEF (or unavailable on Simulator).
enum NFCPSBTImport {
    enum Outcome: Sendable {
        case unavailable
        case cancelled
        case empty
        case payload(Data)
    }

    static func read() async -> Outcome {
        await withCheckedContinuation { continuation in
            guard SimulatorNFC.isAvailable else {
                continuation.resume(returning: .unavailable)
                return
            }
            SimulatorNFC.read(prompt: "Hold a tag with a PSBT") { result in
                switch result {
                case .failure(let error):
                    if let nfc = error as? SimulatorNFCError {
                        switch nfc {
                        case .cancelled: continuation.resume(returning: .cancelled)
                        case .unavailable: continuation.resume(returning: .unavailable)
                        case .failed: continuation.resume(returning: .empty)
                        }
                    } else {
                        continuation.resume(returning: .empty)
                    }
                case .success(let payloads):
                    let large = payloads.filter { $0.count > 50 }
                    let best = (large.isEmpty ? payloads : large).max(by: { $0.count < $1.count })
                    if let best, !best.isEmpty {
                        continuation.resume(returning: .payload(best))
                    } else {
                        continuation.resume(returning: .empty)
                    }
                }
            }
        }
    }
}

struct SimulatorNDEFMessage {
    enum Record {
        case text(String)
        case uri(URL)
        case json(String)
        case binary(type: String, data: Data)
    }

    var records: [Record]

    static func text(_ value: String) -> SimulatorNDEFMessage { SimulatorNDEFMessage(records: [.text(value)]) }
    static func uri(_ url: URL) -> SimulatorNDEFMessage { SimulatorNDEFMessage(records: [.uri(url)]) }
    static func json(_ value: String) -> SimulatorNDEFMessage { SimulatorNDEFMessage(records: [.json(value)]) }
}

#if canImport(CoreNFC)
private final class NFCSessionController: NSObject, NFCNDEFReaderSessionDelegate {
    static let shared = NFCSessionController()

    private var session: NFCNDEFReaderSession?
    private var pendingWrite: NFCNDEFMessage?
    private var readCompletion: ((Result<[Data], Error>) -> Void)?
    private var writeCompletion: ((Result<Void, Error>) -> Void)?
    private var finished = false

    func read(prompt: String, completion: @escaping (Result<[Data], Error>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(SimulatorNFCError.unavailable))
            return
        }
        invalidate()
        finished = false
        readCompletion = completion
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = prompt
        self.session = session
        session.begin()
    }

    func write(_ message: SimulatorNDEFMessage, prompt: String,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(SimulatorNFCError.unavailable))
            return
        }
        invalidate()
        finished = false
        writeCompletion = completion
        pendingWrite = ndefMessage(from: message)
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = prompt
        self.session = session
        session.begin()
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as NSError
        if nfcError.domain == NFCReaderError.errorDomain,
           nfcError.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue {
            finishRead(.failure(SimulatorNFCError.cancelled))
            finishWrite(.failure(SimulatorNFCError.cancelled))
            return
        }
        finishRead(.failure(SimulatorNFCError.failed(error.localizedDescription)))
        finishWrite(.failure(SimulatorNFCError.failed(error.localizedDescription)))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let payloads = messages.flatMap { nfcMessage in
            nfcMessage.records.compactMap(payloadData(from:))
        }
        finishRead(.success(payloads))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else { return }
        if tags.count > 1 {
            session.alertMessage = "More than one tag. Remove extras and try again."
            session.restartPolling()
            return
        }
        guard let pendingWrite else {
            session.connect(to: tag) { error in
                if let error {
                    session.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                tag.readNDEF { message, error in
                    if let message {
                        let payloads = message.records.compactMap(self.payloadData(from:))
                        session.alertMessage = "Tag read."
                        session.invalidate()
                        self.finishRead(.success(payloads))
                    } else {
                        session.invalidate(errorMessage: error?.localizedDescription ?? "Empty tag")
                    }
                }
            }
            return
        }
        session.connect(to: tag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }
            tag.queryNDEFStatus { status, capacity, error in
                if let error {
                    session.invalidate(errorMessage: error.localizedDescription)
                    return
                }
                guard status != .notSupported else {
                    session.invalidate(errorMessage: "Tag is not NDEF.")
                    return
                }
                guard status != .readOnly else {
                    session.invalidate(errorMessage: "Tag is read-only.")
                    return
                }
                guard pendingWrite.length <= capacity else {
                    session.invalidate(errorMessage: "Tag is too small.")
                    return
                }
                tag.writeNDEF(pendingWrite) { error in
                    if let error {
                        session.invalidate(errorMessage: error.localizedDescription)
                    } else {
                        session.alertMessage = "Write complete."
                        session.invalidate()
                        self.finishWrite(.success(()))
                    }
                }
            }
        }
    }

    private func ndefMessage(from message: SimulatorNDEFMessage) -> NFCNDEFMessage {
        let records: [NFCNDEFPayload] = message.records.compactMap { record in
            switch record {
            case .text(let text):
                return NFCNDEFPayload.wellKnownTypeTextPayload(string: text, locale: Locale(identifier: "en"))
            case .uri(let url):
                return NFCNDEFPayload.wellKnownTypeURIPayload(url: url)
            case .json(let json):
                return NFCNDEFPayload(format: .media, type: Data("application/json".utf8),
                                      identifier: Data(), payload: Data(json.utf8))
            case .binary(let type, let data):
                return NFCNDEFPayload(format: .nfcExternal, type: Data(type.utf8),
                                      identifier: Data(), payload: data)
            }
        }
        return NFCNDEFMessage(records: records)
    }

    private func payloadData(from record: NFCNDEFPayload) -> Data? {
        if let text = record.wellKnownTypeTextPayload().0 {
            return Data(text.utf8)
        }
        if let url = record.wellKnownTypeURIPayload() {
            return Data(url.absoluteString.utf8)
        }
        let payload = record.payload
        return payload.isEmpty ? nil : payload
    }

    private func finishRead(_ result: Result<[Data], Error>) {
        guard !finished else { return }
        finished = true
        let completion = readCompletion
        readCompletion = nil
        session = nil
        pendingWrite = nil
        DispatchQueue.main.async { completion?(result) }
    }

    private func finishWrite(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        let completion = writeCompletion
        writeCompletion = nil
        session = nil
        pendingWrite = nil
        DispatchQueue.main.async { completion?(result) }
    }

    private func invalidate() {
        session?.invalidate()
        session = nil
        pendingWrite = nil
    }
}
#endif

struct NFCStandInSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: SimulatorStore
    @State private var pasted = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(store.nfcStandInPrompt).font(.footnote).foregroundStyle(.secondary)
                    TextEditor(text: $pasted)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 120)
                }
                Section {
                    Button("Use pasted text") {
                        let value = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return }
                        store.handleNFCStandInText(value)
                        dismiss()
                    }
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Import file") {
                        dismiss()
                        store.beginNFCStandInFileImport()
                    }
                    if store.nfcStandInKind == .showAddress
                        || store.nfcStandInKind == .verifyAddress
                        || store.nfcStandInKind == .importMultisig
                        || store.nfcStandInKind == .verifySigFile {
                        Button("Scan QR") {
                            dismiss()
                            store.beginNFCToolsQRStandIn()
                        }
                    }
                } footer: {
                    Text("Core NFC is unavailable here (iOS Simulator or device without NFC). Files and paste are the stand-in, not a platformLimit stub. Tag emulation remains out of scope.")
                }
            }
            .navigationTitle(store.nfcStandInTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("CANCEL") { dismiss() } } }
        }
    }
}
