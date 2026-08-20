import Foundation
import ColdcardCore

extension SimulatorStore {
    /// Firmware `actions.ready2sign`: silent `file_picker(suffix='.psbt')` on the MicroSD stand-in.
    func readyToSign() {
        presentReadyToSignChoices(SimulatorCardStandin.psbtFiles(on: .microSD), emptyShowsImportPrompt: true)
    }

    /// Firmware `NFCToolsMenu` `Sign PSBT` → `nfc_sign_psbt` → `NFC.start_psbt_rx()`.
    func beginNFCSignPSBT() {
        beginNFCPSBTReceive(wrapErrors: true)
    }

    /// Firmware empty Ready To Sign `KEY_NFC` and `nfc_sign_psbt`: Core NFC NDEF read.
    func beginNFCPSBTReceive(wrapErrors: Bool = false) {
        nfcStandInKind = .psbt
        nfcReadGeneration += 1
        let generation = nfcReadGeneration
        nfcReceiveNeedsStandIn = !SimulatorNFC.isAvailable
        navigate(to: .nfcReceive)
        guard SimulatorNFC.isAvailable else { return }
        SimulatorNFC.read(prompt: ReadyToSign.nfcReceivePrompt) { [weak self] result in
            guard let self, generation == self.nfcReadGeneration else { return }
            self.consumeNFCPSBTRead(result, wrapErrors: wrapErrors)
        }
    }

    func presentReadyToSignChoices(_ files: [ListedDiskFile], emptyShowsImportPrompt: Bool) {
        switch ReadyToSign.silentOutcome(fileCount: files.count) {
        case .empty:
            if emptyShowsImportPrompt {
                navigate(to: .psbt)
            } else {
                showStory(title: "", body: FirmwareCopy.psbtNoSuitableFiles)
            }
        case .autoOpen:
            guard let file = files.first else { return }
            openReadyToSignFile(file)
        case .picker:
            listedDiskFiles = files.sorted { $0.filename < $1.filename }
            listedFilesAreNFCShare = false
            openMenu(.readyToSignFiles)
        }
    }

    func signAllReadyToSign() {
        var queue: [BatchPSBTItem] = []
        for file in listedDiskFiles {
            if let data = try? Data(contentsOf: file.url) {
                queue.append(BatchPSBTItem(name: file.filename, data: data, url: file.url))
            }
        }
        guard !queue.isEmpty else {
            showStory(title: "", body: FirmwareCopy.psbtNoSuitableFiles)
            return
        }
        batchQueue = queue
        startNextBatchPSBT()
    }

    func signReadyToSignPSBT(id: String) {
        guard let file = listedDiskFiles.first(where: { $0.id == id }) else { return }
        // Firmware `file_picker` `clicked` pops the picker before `sign_psbt_file`.
        back()
        openReadyToSignFile(file)
    }

    func consumeNFCReceiveStandInFile() {
        nfcStandInKind = .psbt
        beginNFCStandInFileImport()
    }

    private func openReadyToSignFile(_ file: ListedDiskFile) {
        guard let data = try? Data(contentsOf: file.url) else {
            showStory(title: "", body: FirmwareCopy.psbtNoSuitableFiles)
            return
        }
        importPurpose = .psbt
        loadPSBT(data: data, source: file.filename, sourceURL: file.url, url: file.url, volume: file.volume,
                 inputMethod: file.volume == .virtDisk ? "vdisk" : "sd")
    }

    private func consumeNFCPSBTRead(_ result: Result<[Data], Error>, wrapErrors: Bool) {
        dismissNFCReceiveIfNeeded()
        switch result {
        case .failure(let error):
            if let nfc = error as? SimulatorNFCError {
                switch nfc {
                case .cancelled:
                    return
                case .unavailable:
                    presentNFCPSBTStandIn()
                case .failed:
                    showStory(title: ReadyToSign.nfcSorryTitle, body: ReadyToSign.nfcNoTagData)
                }
            } else if wrapErrors {
                showStory(title: ReadyToSign.nfcFailedTitle,
                          body: ReadyToSign.nfcSignFailedBody(error.localizedDescription))
            } else {
                showStory(title: ReadyToSign.nfcSorryTitle, body: ReadyToSign.nfcNoTagData)
            }
        case .success(let payloads):
            consumeNFCPSBTPayloads(payloads)
        }
    }

    private func consumeNFCPSBTPayloads(_ payloads: [Data]) {
        if payloads.isEmpty {
            showStory(title: ReadyToSign.nfcSorryTitle, body: ReadyToSign.nfcNoTagData)
            return
        }
        guard let data = ReadyToSign.psbtPayload(fromNDEF: payloads) else {
            showStory(title: ReadyToSign.nfcSorryTitle, body: ReadyToSign.nfcMissingPSBT)
            return
        }
        loadPSBT(data: data, source: "NFC", inputMethod: "nfc")
    }

    private func dismissNFCReceiveIfNeeded() {
        if screen == .nfcReceive {
            back()
        }
    }

    private func presentNFCPSBTStandIn() {
        nfcStandInKind = .psbt
        nfcReceiveNeedsStandIn = true
        if screen != .nfcReceive {
            navigate(to: .nfcReceive)
        }
        if interfaceMode == .phone {
            showNFCStandIn = true
        }
    }
}
