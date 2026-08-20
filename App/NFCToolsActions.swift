import Foundation
import ColdcardCore

extension SimulatorStore {
    /// Firmware `nfc.start_msg_sign` / `address_show_and_share` / `verify_address_nfc` / `import_multisig_nfc`.
    func beginNFCSignMessage() {
        beginNFCToolsRead(.signMessage)
    }

    /// Firmware `NFC.verify_sig_nfc` (`digest_check=False`).
    func beginNFCVerifySigFile() {
        beginNFCToolsRead(.verifySigFile)
    }

    func beginNFCShowAddress() {
        beginNFCToolsRead(.showAddress)
    }

    func beginNFCVerifyAddress() {
        beginNFCToolsRead(.verifyAddress)
    }

    func beginNFCToolsImportMultisig() {
        beginNFCToolsRead(.importMultisig)
    }

    func beginNFCToolsRead(_ kind: NFCStandInKind) {
        nfcStandInKind = kind
        nfcReadGeneration += 1
        let generation = nfcReadGeneration
        if SimulatorNFC.isAvailable {
            SimulatorNFC.read(prompt: FirmwareCopy.nfcTapPrompt) { [weak self] result in
                guard let self, generation == self.nfcReadGeneration else { return }
                switch result {
                case .failure(let error):
                    if let nfc = error as? SimulatorNFCError {
                        switch nfc {
                        case .cancelled: return
                        case .unavailable: self.presentNFCToolsStandIn()
                        case .failed: self.showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
                        }
                    } else {
                        self.showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
                    }
                case .success(let payloads):
                    self.consumeNFCToolsPayloads(payloads)
                }
            }
            return
        }
        presentNFCToolsStandIn()
    }

    func presentNFCToolsStandIn() {
        if interfaceMode == .phone {
            showNFCStandIn = true
        } else {
            showStory(title: nfcStandInTitle, body: FirmwareCopy.nfcToolsStandIn,
                      onConfirm: .nfcToolsStandIn)
        }
    }

    func finishNFCToolsPaste() {
        let text = passphraseInput
        textEntryIsNFCTools = false
        passphraseInput = ""
        back()
        consumeNFCToolsText(text)
    }

    func beginNFCToolsQRStandIn() {
        nfcAwaitingQRStandIn = true
        showScanner = true
    }

    func consumeNFCToolsPayloads(_ payloads: [Data]) {
        if payloads.isEmpty {
            showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
            return
        }
        if nfcStandInKind == .signMessage {
            for payload in payloads {
                guard let text = String(data: payload, encoding: .utf8),
                      NFCShare.nfcSignMessagePayload(from: text) != nil else { continue }
                presentNFCSignMessage(text)
                return
            }
            showStory(title: "", body: FirmwareCopy.nfcSignMessageMissing)
            return
        }
        if nfcStandInKind == .verifySigFile {
            for payload in payloads {
                guard let text = String(data: payload, encoding: .utf8),
                      text.contains("SIGNED MESSAGE") else { continue }
                verifySigFile(text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                              filename: "nfc", digestCheck: false)
                return
            }
            showStory(title: "", body: FirmwareCopy.nfcSignedMessageMissing)
            return
        }
        let texts = payloads.compactMap { String(data: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let text = texts.max(by: { $0.count < $1.count }) else {
            showStory(title: "Sorry!", body: nfcToolsMissingMessage)
            return
        }
        consumeNFCToolsText(text)
    }

    func consumeNFCToolsText(_ text: String) {
        nfcAwaitingQRStandIn = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showStory(title: "Sorry!", body: nfcToolsMissingMessage)
            return
        }
        switch nfcStandInKind {
        case .psbt:
            handleNFCStandInText(trimmed)
        case .showAddress: presentNFCShowAddress(trimmed)
        case .verifyAddress: presentNFCVerifyAddress(trimmed)
        case .importMultisig: presentNFCImportMultisig(trimmed)
        case .signMessage: presentNFCSignMessage(text)
        case .verifySigFile:
            guard trimmed.contains("SIGNED MESSAGE") else {
                showStory(title: "", body: FirmwareCopy.nfcSignedMessageMissing)
                return
            }
            verifySigFile(text: trimmed, filename: "nfc", digestCheck: false)
        default: break
        }
    }

    /// Firmware `NFC.start_msg_sign` → `approve_msg_sign(..., msg_sign_request=)` (240, RFC).
    func presentNFCSignMessage(_ text: String) {
        guard NFCShare.nfcSignMessagePayload(from: text) != nil else {
            showStory(title: "", body: FirmwareCopy.nfcSignMessageMissing)
            return
        }
        guard let request = BitcoinMessageSigner.parseSignRequest(text) else {
            showStory(title: "", body: "Problem: MSG required\n\nMessage to be signed must be a single line of ASCII text.")
            return
        }
        messageSignDoneMode = .nfcRFC
        messageSourceFilename = "msg_sign.txt"
        applySignRequest(request)
    }

    func shareNFCShownAddress() {
        guard let address = pendingNFCShownAddress else { return }
        SimulatorNFCWriter.shared.shareText(address.address) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                let note: String
                if case SimulatorNFCError.unavailable = error {
                    note = FirmwareCopy.nfcSessionUnavailable
                } else {
                    note = error.localizedDescription
                }
                self.showStory(title: "", body: note)
            }
        }
    }

    func showNFCShownAddressQR() {
        guard let address = pendingNFCShownAddress else { return }
        qrPresentation = QRPresentation(title: address.path, payload: address.address, sensitive: false)
    }

    func startMessageSigningFromNFCVerifiedAddress() {
        guard pendingOwnershipCanSign, let address = pendingNFCShownAddress else { return }
        selectedAddress = address
        addressType = pendingNFCShownAddressType
        startMessageSigningFromAddress()
    }

    func commitNFCImportedMultisig() {
        guard var wallet = pendingNFCMultisig else {
            back()
            return
        }
        if pendingNFCMultisigDuplicate {
            back()
            return
        }
        let names = preferences.importedMultisigWallets.map(\.name)
        wallet.name = MultisigWalletConfig.uniqueName(wallet.name, existing: names)
        preferences.importedMultisigWallets.append(wallet)
        persistPreferencesQuietly()
        pendingNFCMultisig = nil
        statusMessage = FirmwareCopy.nfcSavedPause
        back()
    }

    func showNFCImportedMultisigXPUBs() {
        guard let wallet = pendingNFCMultisig else { return }
        let confirm = wallet.confirmImportStory(existing: preferences.importedMultisigWallets)
        pendingNFCMultisigShowingXPUBs.toggle()
        if pendingNFCMultisigShowingXPUBs {
            showStory(title: wallet.name, body: wallet.detailText(verbose: false),
                      onConfirm: .enrollImportedMultisig)
        } else {
            showStory(title: "", body: confirm.body, onConfirm: .enrollImportedMultisig)
        }
    }

    private var nfcToolsMissingMessage: String {
        switch nfcStandInKind {
        case .showAddress: FirmwareCopy.nfcAddressPathMissing
        case .verifyAddress: FirmwareCopy.nfcAddressMissing
        case .importMultisig: FirmwareCopy.nfcMultisigMissing
        case .signMessage: FirmwareCopy.nfcSignMessageMissing
        case .verifySigFile: FirmwareCopy.nfcSignedMessageMissing
        default: FirmwareCopy.nfcNoTagData
        }
    }

    private func presentNFCShowAddress(_ text: String) {
        guard let root = rootKey else {
            showStory(title: "ERROR", body: FirmwareCopy.nfcShowAddressFailed + "Need a seed first.")
            return
        }
        do {
            let shown = try PushTx.parseShowAddress(text)
            let path = try DerivationPath(shown.path)
            let derived = try BitcoinAddress.derive(root: root, path: path, type: shown.type)
            pendingNFCShownAddress = derived
            pendingNFCShownAddressType = shown.type
            pendingOwnershipCanSign = true
            selectedAddress = derived
            addressType = shown.type
            let body = """
            \(Self.chunkAddress(derived.address))

            = \(derived.path)

            \(FirmwareCopy.showAddressCompare)
            """
            showStory(title: "Address:", body: body, onConfirm: .nfcShowAddress,
                      hintQR: true, hintNFC: preferences.nfcSharingEnabled)
        } catch {
            showStory(title: "ERROR", body: FirmwareCopy.nfcShowAddressFailed + error.localizedDescription)
        }
    }

    private func presentNFCVerifyAddress(_ text: String) {
        guard let root = rootKey else {
            showStory(title: "ERROR", body: FirmwareCopy.nfcVerifyFailed + "Need a seed first.")
            return
        }
        do {
            let parsed = try PushTx.parseBIP21(text)
            beginWorking(.wait)
            let accounts = Array(Set([UInt32(0), addressAccount])).sorted()
            let wallets = preferences.importedMultisigWallets
            let wifKeys = record?.wifKeys ?? []
            Task {
                let result = await Task.detached(priority: .userInitiated) { () -> Result<AddressOwnershipHit, Error> in
                    do {
                        return .success(try AddressOwnership.searchUX(
                            address: parsed.address, args: parsed.args, root: root,
                            wifKeys: wifKeys, wallets: wallets, accounts: accounts, perChain: 200
                        ))
                    } catch {
                        return .failure(error)
                    }
                }.value
                endWorking()
                switch result {
                case .success(let hit):
                    presentVerifiedAddress(parsed.address, hit: hit)
                case .failure(let error):
                    let addr = SimulatorStore.chunkAddress(parsed.address)
                    if let ownership = error as? AddressOwnershipError, case .notFound = ownership {
                        showStory(title: "Unknown Address",
                                  body: "\(addr)\n\n\(error.localizedDescription)")
                    } else if let ownership = error as? AddressOwnershipError, case .invalidOnChain = ownership {
                        showStory(title: "Unknown Address",
                                  body: "\(addr)\n\n\(error.localizedDescription)")
                    } else {
                        showStory(title: "ERROR",
                                  body: FirmwareCopy.nfcVerifyFailed + error.localizedDescription)
                    }
                }
            }
        } catch {
            showStory(title: "", body: FirmwareCopy.nfcAddressMissing)
        }
    }

    private func presentVerifiedAddress(_ address: String, hit: AddressOwnershipHit) {
        var body = SimulatorStore.chunkAddress(address)
        pendingOwnershipCanSign = false
        pendingNFCShownAddress = nil
        switch hit {
        case .singlesig(let name, let derived):
            pendingNFCShownAddress = derived
            pendingNFCShownAddressType = addressType(for: derived)
            pendingOwnershipCanSign = true
            selectedAddress = derived
            body += """


            Found in wallet:
              \(name)
            Derivation path:
              \(derived.path)

            Press (0) to sign message with this key.
            """
        case .wif(let index):
            body += "\n\nFound in WIF store at index \(index)"
        case .multisig(let name, let path):
            body += """


            Found in wallet:
              \(name)
            Derivation path:
              \(path)
            """
        }
        showStory(title: "Verified Address", body: body, onConfirm: .nfcVerifiedAddress,
                  hintQR: true, hintNFC: false)
        if pendingNFCShownAddress == nil {
            pendingNFCShownAddress = DerivedAddress(index: 0, change: false, path: "", address: address,
                                                    publicKeyHex: "", scriptPubKeyHex: "")
        }
    }

    private func addressType(for derived: DerivedAddress) -> AddressType {
        if derived.path.contains("/84h/") { return .nativeSegwit }
        if derived.path.contains("/49h/") { return .wrappedSegwit }
        if derived.path.contains("/86h/") { return .taproot }
        return .legacy
    }

    private func presentNFCImportMultisig(_ text: String) {
        guard PushTx.looksLikeMultisig(text) else {
            showStory(title: "", body: FirmwareCopy.nfcMultisigMissing)
            return
        }
        guard let root = rootKey else {
            showStory(title: "ERROR", body: FirmwareCopy.nfcImportFailed + "Need a seed first.")
            return
        }
        beginWorking(.wait)
        let existing = preferences.importedMultisigWallets
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (ImportedMultisigWallet?, String?) in
                do {
                    let parsed = try PushTx.parseMultisigConfig(text)
                    let context = MultisigImportContext(root: root, allowUnsorted: false, disableChecks: false)
                    let wallet = try MultisigWalletConfig.importFile(parsed.config, nameHint: parsed.name,
                                                                     context: context)
                    return (wallet, nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            endWorking()
            if let wallet = result.0 {
                pendingNFCMultisig = wallet
                pendingNFCMultisigShowingXPUBs = false
                let confirm = wallet.confirmImportStory(existing: existing)
                pendingNFCMultisigDuplicate = confirm.isDuplicate
                if confirm.isDuplicate {
                    showStory(title: "", body: confirm.body)
                } else {
                    showStory(title: "", body: confirm.body, onConfirm: .enrollImportedMultisig)
                }
            } else {
                showStory(title: "ERROR",
                          body: FirmwareCopy.nfcImportFailed + (result.1 ?? ""))
            }
        }
    }
}
