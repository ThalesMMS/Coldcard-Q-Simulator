import Foundation
import UIKit
import ColdcardCore

extension SimulatorStore {
    /// Firmware `actions.import_xprv` (`ephemeral=item.arg`) via `import_export_prompt`.
    func startImportXPRV() {
        let ephemeral = currentMenu == .temporarySeed || currentMenu == .temporarySeedImport || pendingEphemeral
        pendingEphemeral = ephemeral
        if !ephemeral, hasSeed {
            showStory(title: "Import XPRV", body: FirmwareCopy.needClearSeed)
            return
        }
        importPurpose = .xprv
        ephemeralOrigin = FirmwareCopy.importedXPRVOrigin
        scanExpectSecret = true
        showStory(
            title: "",
            body: FirmwareCopy.xprvImportPrompt(
                virtualDiskEnabled: virtualDiskEnabled,
                nfcEnabled: preferences.nfcSharingEnabled
            ),
            onConfirm: .importXPRVSource,
            hintQR: true,
            hintNFC: preferences.nfcSharingEnabled
        )
    }

    func handleXPRVStoryKey(_ value: String) -> Bool {
        guard story.onConfirm == .importXPRVSource else { return false }
        switch value.lowercased() {
        case "1":
            pickXPRVFromFiles()
            return true
        case "b":
            importXPRVFromVolume(.microSD)
            return true
        case "2":
            importXPRVFromVolume(.virtDisk)
            return true
        default:
            return false
        }
    }

    func handleXPRVNFC() -> Bool {
        guard screen == .story, story.onConfirm == .importXPRVSource else { return false }
        guard preferences.nfcSharingEnabled else { return true }
        importXPRVFromNFC()
        return true
    }

    func handleXPRVQRKey() -> Bool {
        guard screen == .story, story.onConfirm == .importXPRVSource else { return false }
        beginXPRVQRScan()
        return true
    }

    func confirmXPRVStory(_ action: StoryConfirmAction) -> Bool {
        guard action == .importXPRVSource else { return false }
        story.onConfirm = .importXPRVSource
        return true
    }

    func pickXPRVFromFiles() {
        importPurpose = .xprv
        showFileImporter = true
    }

    func beginXPRVQRScan() {
        importPurpose = .xprv
        scanExpectSecret = true
        showScanner = true
    }

    /// Firmware `file_picker(suffix='.txt', min_size=50, max_size=2000, taster=contains_xprv)`.
    func importXPRVFromVolume(_ volume: SimulatorCardStandin.Volume) {
        if volume == .virtDisk, !virtualDiskEnabled { return }
        let files = SimulatorCardStandin.listRootFiles(on: volume, minSize: 50, maxSize: 2000)
            .filter { $0.filename.lowercased().hasSuffix(".txt") }
            .filter { file in
                guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { return false }
                return FirmwareImportPrompt.firstPrivateKeyLine(in: text) != nil
            }
        guard !files.isEmpty else {
            showStory(title: "", body: FirmwareCopy.xprvFileNoneMsg)
            return
        }
        if files.count == 1, let file = files.first, let text = try? String(contentsOf: file.url, encoding: .utf8) {
            consumeImportedXPRVText(text)
            return
        }
        pickXPRVFromFiles()
    }

    /// Firmware `NFC.read_extended_private_key()` — Core NFC NDEF (not HCE).
    func importXPRVFromNFC() {
        guard preferences.nfcSharingEnabled else { return }
        if SimulatorNFC.isAvailable {
            SimulatorNFC.read(prompt: FirmwareCopy.nfcTapPrompt) { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let payloads):
                        self?.consumeImportedXPRVNFCPayloads(payloads)
                    case .failure(let error):
                        if let nfc = error as? SimulatorNFCError {
                            switch nfc {
                            case .cancelled:
                                break
                            case .unavailable:
                                self?.importXPRVFromClipboardStandIn()
                            case .failed:
                                self?.showStory(title: "", body: FirmwareCopy.xprvNFCMissing)
                            }
                        } else {
                            self?.showStory(title: "", body: FirmwareCopy.xprvNFCMissing)
                        }
                    }
                }
            }
            return
        }
        importXPRVFromClipboardStandIn()
    }

    func consumeImportedXPRVFile(_ data: Data) {
        consumeImportedXPRVText(String(decoding: data, as: UTF8.self))
    }

    func consumeImportedXPRVText(_ text: String) {
        ephemeralOrigin = FirmwareCopy.importedXPRVOrigin
        if let token = FirmwareImportPrompt.parseExtendedPrivateKeyToken(text) {
            importExtendedKey(token, temporary: pendingEphemeral)
            return
        }
        showStory(title: "FAILED", body: FirmwareCopy.xprvImportFailed)
    }

    func consumeImportedXPRVNFCPayloads(_ payloads: [Data]) {
        guard let text = FirmwareImportPrompt.extendedPrivateKey(fromNFCPayloads: payloads) else {
            showStory(title: "", body: FirmwareCopy.xprvNFCMissing)
            return
        }
        consumeImportedXPRVText(text)
    }

    private func importXPRVFromClipboardStandIn() {
        guard let text = UIPasteboard.general.string,
              FirmwareImportPrompt.parseExtendedPrivateKeyToken(text) != nil else {
            showStory(title: "", body: FirmwareCopy.xprvNFCMissing)
            return
        }
        consumeImportedXPRVText(text)
    }
}
