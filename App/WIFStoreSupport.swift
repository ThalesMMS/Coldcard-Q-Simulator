import Foundation
import UIKit
import ColdcardCore

nonisolated enum WIFAddressPickerPurpose: Equatable, Sendable {
    case descriptors
    case addresses
    case sign
}

extension SimulatorStore {
    var wifKeys: [WIFStoreItem] { record?.wifKeys ?? [] }

    var selectedWIF: WIFStoreItem? {
        guard let selectedWIFIndex, wifKeys.indices.contains(selectedWIFIndex) else { return nil }
        return wifKeys[selectedWIFIndex]
    }

    func presentWIFStoreMenu() {
        if wifKeys.isEmpty {
            showStory(title: "WIF Store", body: FirmwareCopy.wifStoreIntro, onConfirm: .openWIFStore)
            return
        }
        openMenu(.wifStore)
    }

    func beginWIFImport() {
        showStory(title: "",
                  body: FirmwareCopy.wifImportPrompt(virtualDiskEnabled: virtualDiskEnabled,
                                                     nfcEnabled: preferences.nfcSharingEnabled),
                  onConfirm: .wifImportPrompt)
    }

    func importWIFFromText(_ text: String, announceSuccess: Bool = false) {
        beginWorking(.wait)
        let existing = wifKeys
        let network = self.network
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([WIFStoreItem]?, String?) in
                do {
                    return (try WIFStoreLogic.parseImport(text, network: network, existing: existing), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            endWorking()
            if let merged = result.0 {
                persistWIFKeys(merged)
                if announceSuccess {
                    showStory(title: "Success", body: FirmwareCopy.wifSaved)
                } else {
                    openMenu(.wifStore, remember: false)
                }
            } else {
                showStory(title: "Failure", body: "Failed to import WIF.\n\n\(result.1 ?? "")")
            }
        }
    }

    func importWIFFromFilePicker() {
        importPurpose = .wif
        showFileImporter = true
    }

    func importWIFFromVirtualDisk() {
        importWIFFromVolume(.virtDisk)
    }

    func importWIFFromLowerSlot() {
        importWIFFromVolume(.microSD)
    }

    func importWIFFromVolume(_ volume: SimulatorCardStandin.Volume) {
        if volume == .virtDisk, !virtualDiskEnabled { return }
        let files = SimulatorCardStandin.listRootFiles(on: volume, minSize: 51, maxSize: 11_000)
            .filter { file in
                let lower = file.filename.lowercased()
                return lower.hasSuffix(".txt") || lower.hasSuffix(".csv")
            }
        guard !files.isEmpty else {
            showStory(title: "", body: "Must contain WIF(s)")
            return
        }
        if files.count == 1, let file = files.first, let text = try? String(contentsOf: file.url, encoding: .utf8) {
            consumeWIFImportText(text)
            return
        }
        importPurpose = .wif
        showFileImporter = true
    }

    func importWIFFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStory(title: "Sorry!", body: "No WIF text found.")
            return
        }
        consumeWIFImportText(text)
    }

    func beginManualWIFEntry() {
        textEntryIsWIF = true
        passphraseInput = ""
        navigate(to: .passphrase)
    }

    func commitManualWIFEntry() {
        let text = passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        textEntryIsWIF = false
        passphraseInput = ""
        back()
        guard !text.isEmpty else { return }
        importWIFFromText(text)
    }

    func openWIFItem(_ index: Int) {
        selectedWIFIndex = index
        openMenu(.wifStoreItem)
    }

    func showWIFDetail() {
        guard let item = selectedWIF,
              let wif = try? WIFStoreLogic.encodedWIF(item, network: network) else { return }
        pendingExport = nil
        walletExportTitle = "WIF"
        walletExportText = "\(wif)\n\nPrivkey:\n\(item.privateKeyHex)\n\nPubkey:\n\(item.publicKeyHex)"
        exportFilename = "wif.txt"
        navigate(to: .walletExport)
    }

    func beginWIFDescriptors() {
        wifAddressPicker = .descriptors
        openMenu(.messageAddressFormat)
    }

    func beginWIFAddresses() {
        wifAddressPicker = .addresses
        openMenu(.messageAddressFormat)
    }

    func beginWIFSignMessage() {
        wifAddressPicker = .sign
        openMenu(.messageAddressFormat)
    }

    func pickWIFAddressType(_ type: AddressType) {
        let purpose = wifAddressPicker
        wifAddressPicker = nil
        guard let item = selectedWIF, let publicKey = item.publicKey else { return }
        switch purpose {
        case .descriptors:
            do {
                pendingExport = nil
                walletExportTitle = "Descriptor"
                walletExportText = try WIFStoreLogic.descriptor(publicKeyHex: item.publicKeyHex, type: type)
                exportFilename = WIFStoreLogic.descriptorFilename(type: type)
                navigate(to: .walletExport)
            } catch { present(error) }
        case .addresses:
            do {
                let address = try BitcoinAddress.address(publicKey: publicKey, type: type, network: network)
                pendingExport = nil
                walletExportTitle = type.displayName
                walletExportText = SimulatorStore.chunkAddress(address)
                exportFilename = "wif_addr.txt"
                navigate(to: .walletExport)
            } catch { present(error) }
        case .sign:
            wifSignPrivateKey = item.privateKey
            messageAddressType = type
            messagePath = "m"
            messagePathLocked = true
            messageMaxLength = BitcoinMessageSigner.maximumLength
            messageSourceFilename = "msg_sign.txt"
            messageText = ""
            signedMessage = nil
            showStory(title: "",
                      body: FirmwareCopy.wifSignImportPrompt(virtualDiskEnabled: virtualDiskEnabled,
                                                             nfcEnabled: preferences.nfcSharingEnabled),
                      onConfirm: .wifSignImport)
        case nil:
            break
        }
    }

    func beginManualWIFMessage() {
        messageText = ""
        signedMessage = nil
        messageMaxLength = BitcoinMessageSigner.uxInputMaximumLength
        messageSourceFilename = "msg_sign.txt"
        navigate(to: .messageSigning)
    }

    func applyWIFMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            messageText = try BitcoinMessageSigner.validate(trimmed, maxLength: BitcoinMessageSigner.maximumLength)
        } catch {
            showStory(title: "", body: "Problem: \(error.localizedDescription)\n\nMessage to be signed must be a single line of ASCII text.")
            return
        }
        messagePath = "m"
        messagePathLocked = true
        messageMaxLength = BitcoinMessageSigner.maximumLength
        signedMessage = nil
        presentWIFMessageApproval()
    }

    func presentWIFMessageApproval() {
        guard let item = selectedWIF, let publicKey = item.publicKey else { return }
        let address: String
        do {
            address = try BitcoinAddress.address(publicKey: publicKey, type: messageAddressType, network: network)
        } catch {
            present(error)
            return
        }
        do {
            _ = try BitcoinMessageSigner.validate(messageText, maxLength: messageMaxLength)
        } catch {
            showStory(title: "", body: "Problem: \(error.localizedDescription)\n\nMessage to be signed must be a single line of ASCII text.")
            return
        }
        showStory(title: "", body: """
        Ok to sign this?
              --=--
        \(messageText)
              --=--

        Using the key associated with address:

        m =>
        \(Self.chunkAddress(address))

        \(FirmwareCopy.messageSignFooter)
        """, onConfirm: .approveMessageSign)
    }

    func performWIFMessageSignature() {
        guard let privateKey = wifSignPrivateKey, let item = selectedWIF, let publicKey = item.publicKey else { return }
        beginWorking(.generating)
        let text = messageText
        let type = messageAddressType
        let network = self.network
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (SignedBitcoinMessage?, String?) in
                do {
                    return (try BitcoinMessageSigner.sign(text, privateKey: privateKey, publicKey: publicKey,
                                                          type: type, network: network, path: "m"), nil)
                } catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            wifSignPrivateKey = nil
            signedMessage = result.0
            errorMessage = result.1
            if signedMessage != nil { presentSignedMessageExportPrompt() }
        }
    }

    func confirmDeleteWIF() {
        showStory(title: "", body: FirmwareCopy.wifDeleteConfirm, onConfirm: .deleteWIF)
    }

    func deleteSelectedWIF() {
        guard var record, let selectedWIFIndex, record.wifKeys.indices.contains(selectedWIFIndex) else { return }
        record.wifKeys.remove(at: selectedWIFIndex)
        self.record = record
        try? persistRecord()
        self.selectedWIFIndex = nil
        openMenu(.wifStore, remember: false)
    }

    func confirmClearAllWIF() {
        showStory(title: "", body: FirmwareCopy.wifClearAll, onConfirm: .clearAllWIF, confirmCode: "4")
    }

    func clearAllWIFKeys() {
        persistWIFKeys([])
        openMenu(.wifStore, remember: false)
    }

    func exportAllWIFKeys() {
        let network = self.network
        let keys = wifKeys
        pendingExport = nil
        walletExportTitle = "WIF Store"
        walletExportText = keys.compactMap { try? WIFStoreLogic.encodedWIF($0, network: network) }.joined(separator: "\n")
        exportFilename = "wif_store.txt"
        navigate(to: .walletExport)
    }

    func visualizeScannedWIF(_ wif: String) {
        guard let decoded = try? WIF.decode(wif) else { return }
        pendingVisualizedWIF = wif
        let chain = decoded.isTestnet ? "XTN" : "BTC"
        var body = "\(wif)\n\nchain: \(chain)\n\nPrivkey:\n\(decoded.privateKeyHex)\n\nPubkey:\n\(decoded.publicKeyHex)"
        let matchingChain = decoded.isTestnet == (network != .mainnet)
        if decoded.compressed && matchingChain {
            body += "\n\nPress (1) to import to WIF Store."
            showStory(title: "WIF Key", body: body, onConfirm: .importVisualizedWIF)
        } else {
            showStory(title: "WIF Key", body: body)
        }
    }

    func importVisualizedWIF() {
        guard let wif = pendingVisualizedWIF else { return }
        pendingVisualizedWIF = nil
        importWIFFromText(wif, announceSuccess: true)
    }

    func applyPendingWIFKeys(to record: inout StoredWalletRecord) {
        if let keys = pendingWIFKeys {
            record.wifKeys = keys
            pendingWIFKeys = nil
        }
    }

    func persistWIFKeys(_ keys: [WIFStoreItem]) {
        guard var record else { return }
        record.wifKeys = keys
        self.record = record
        try? persistRecord()
    }

    func consumeImportedWIFFile(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        consumeWIFImportText(text)
    }

    func consumeWIFImportText(_ text: String) {
        if wifSignPrivateKey != nil {
            applyWIFMessage(text)
        } else {
            importWIFFromText(text)
        }
    }

    func handleWIFStoryKey(_ value: String) -> Bool {
        let key = value.lowercased()
        if story.onConfirm == .wifImportPrompt {
            if key == "0" { beginManualWIFEntry(); return true }
            if key == "1" { importWIFFromFilePicker(); return true }
            if key == "b" { importWIFFromLowerSlot(); return true }
            if key == "2" { importWIFFromVirtualDisk(); return true }
            return false
        }
        if story.onConfirm == .wifSignImport {
            if key == "0" { beginManualWIFMessage(); return true }
            if key == "1" { importWIFFromFilePicker(); return true }
            if key == "b" { importWIFFromLowerSlot(); return true }
            if key == "2" { importWIFFromVirtualDisk(); return true }
            return false
        }
        if story.onConfirm == .importVisualizedWIF, key == "1" {
            importVisualizedWIF()
            return true
        }
        return false
    }

    func handleWIFNFC() -> Bool {
        guard preferences.nfcSharingEnabled else { return false }
        if story.onConfirm == .wifImportPrompt || story.onConfirm == .wifSignImport {
            importWIFFromNFC()
            return true
        }
        return false
    }

    func importWIFFromNFC() {
        guard preferences.nfcSharingEnabled else { return }
        if SimulatorNFC.isAvailable {
            SimulatorNFC.read(prompt: "Hold a tag with a WIF") { [weak self] result in
                Task { @MainActor in
                    switch result {
                    case .success(let payloads):
                        let text = payloads.compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n")
                        self?.consumeWIFImportText(text)
                    case .failure:
                        self?.importWIFFromClipboard()
                    }
                }
            }
        } else {
            importWIFFromClipboard()
        }
    }

    func handleWIFScannedText(_ text: String) -> Bool {
        if story.onConfirm == .wifImportPrompt {
            importWIFFromText(text)
            return true
        }
        if story.onConfirm == .wifSignImport {
            applyWIFMessage(text)
            return true
        }
        if (try? WIF.decode(text)) != nil {
            visualizeScannedWIF(text)
            return true
        }
        return false
    }

    func confirmWIFStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .openWIFStore:
            back()
            openMenu(.wifStore)
        case .deleteWIF:
            deleteSelectedWIF()
        case .clearAllWIF:
            clearAllWIFKeys()
        case .importVisualizedWIF:
            back()
        case .wifImportPrompt:
            story.onConfirm = .wifImportPrompt
        case .wifSignImport:
            story.onConfirm = .wifSignImport
        default:
            return false
        }
        return true
    }

    func performWIFCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .importWIF: beginWIFImport()
        case .openWIFItem(let index): openWIFItem(index)
        case .wifDetail: showWIFDetail()
        case .wifDescriptors: beginWIFDescriptors()
        case .wifAddresses: beginWIFAddresses()
        case .wifSignMSG: beginWIFSignMessage()
        case .deleteWIF: confirmDeleteWIF()
        case .exportAllWIF: exportAllWIFKeys()
        case .clearAllWIF: confirmClearAllWIF()
        default: return false
        }
        return true
    }
}
