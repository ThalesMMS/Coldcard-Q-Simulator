import Foundation
import ColdcardCore

nonisolated struct MultisigMenuSnapshot: Equatable, Sendable {
    var wallets: [ImportedMultisigWallet] = []
    var selectedIndex: Int? = nil
    var fullAddressView = false
    var skipChecks = false
    var allowUnsorted = false
    var trustPolicy = 1
}

extension SimulatorStore {
    var selectedMultisig: ImportedMultisigWallet? {
        guard let selectedMultisigIndex,
              preferences.importedMultisigWallets.indices.contains(selectedMultisigIndex) else {
            return nil
        }
        return preferences.importedMultisigWallets[selectedMultisigIndex]
    }

    var effectiveMultisigTrustPolicy: Int {
        if let stored = preferences.psbtMultisigTrust { return stored }
        return preferences.importedMultisigWallets.isEmpty ? 1 : 0
    }

    var multisigMenuSnapshot: MultisigMenuSnapshot {
        MultisigMenuSnapshot(
            wallets: preferences.importedMultisigWallets,
            selectedIndex: selectedMultisigIndex,
            fullAddressView: preferences.fullMultisigAddressView,
            skipChecks: skipMultisigChecks,
            allowUnsorted: preferences.allowUnsortedMultisig,
            trustPolicy: effectiveMultisigTrustPolicy
        )
    }

    func persistMultisigWallets(_ wallets: [ImportedMultisigWallet]) {
        preferences.importedMultisigWallets = wallets
        persistPreferencesQuietly()
    }

    func performMultisigCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .noneSetupYet:
            showStory(title: "", body: FirmwareCopy.noMultisigYet)
        case .openMultisigWallet(let index):
            guard preferences.importedMultisigWallets.indices.contains(index) else { return true }
            selectedMultisigIndex = index
            openMenu(.multisigWallet)
        case .importMultisig:
            beginMultisigImport()
        case .nfcImportMultisig:
            importMultisigFromNFC()
        case .exportMultisigXPUB:
            showStory(title: "", body: FirmwareCopy.exportMultisigXPUB(coinType: network.coinType),
                      onConfirm: .continueExportXPUB)
        case .createAirgapped:
            beginCreateAirgapped()
        case .trustPSBTMenu:
            showStory(title: "", body: FirmwareCopy.trustPSBT, onConfirm: .continueTrustPSBT)
        case .skipChecksMenu:
            if skipMultisigChecks {
                openMenu(.skipChecks)
            } else {
                showStory(title: "", body: FirmwareCopy.skipChecks, onConfirm: .continueSkipChecks, confirmCode: "4")
            }
        case .fullAddressViewMenu:
            openMenu(.fullAddressView)
        case .unsortedMultisigMenu:
            if preferences.allowUnsortedMultisig {
                let unsortedNames = preferences.importedMultisigWallets.filter { !$0.bip67 }.map(\.name)
                if !unsortedNames.isEmpty {
                    showStory(title: "", body: FirmwareCopy.unsortedMustRemove(unsortedNames))
                } else {
                    openMenu(.unsortedMultisig)
                }
            } else {
                showStory(title: "", body: FirmwareCopy.unsortedMultisig, onConfirm: .continueUnsortedMultisig, confirmCode: "4")
            }
        case .setTrustPSBT(let policy):
            preferences.psbtMultisigTrust = policy
            persistPreferencesQuietly()
            back()
        case .setSkipChecks(let value):
            skipMultisigChecks = value
            back()
        case .setFullAddressView(let value):
            preferences.fullMultisigAddressView = value
            persistPreferencesQuietly()
            back()
        case .setUnsortedMultisig(let value):
            preferences.allowUnsortedMultisig = value
            persistPreferencesQuietly()
            back()
        case .viewMultisigDetail:
            showSelectedMultisigDetail()
        case .renameMultisig:
            beginRenameMultisig()
        case .deleteMultisig:
            guard let wallet = selectedMultisig else { return true }
            showStory(title: "", body: FirmwareCopy.deleteMultisig(wallet.name), onConfirm: .confirmDeleteMultisig)
        case .exportMultisigColdcard:
            exportSelectedMultisig { wallet, _ in
                Data(wallet.coldcardExport(headerComment: "exported by simulator").utf8)
            }
        case .exportMultisigElectrum:
            guard let wallet = selectedMultisig else { return true }
            let derivs = Array(Set(wallet.cosigners.map(\.derivation))).sorted()
            let dsum = derivs.count == 1 ? derivs[0] : "Varies (\(derivs.count))"
            let msg = "The new wallet will have derivation path:\n  \(dsum)\n and use \(wallet.addressFormat.exportLabel) addresses.\n"
            showStory(title: "", body: FirmwareCopy.electrumExport(msg), onConfirm: .continueElectrumExport)
        case .viewMultisigDescriptor:
            showSelectedMultisigDescriptor()
        case .exportMultisigDescriptor:
            exportSelectedMultisig { wallet, _ in
                Data(try wallet.descriptor().utf8)
            }
        case .exportMultisigBitcoinCore:
            exportSelectedMultisig { wallet, _ in
                Data(try wallet.bitcoinCoreExport().utf8)
            }
        case .exploreMultisig(let index):
            exploringMultisigIndex = index
            lastAddressExplorerLabel = preferences.importedMultisigWallets.indices.contains(index)
                ? preferences.importedMultisigWallets[index].name : nil
            addressAllowChange = true
            addressChange = false
            customSingleAddress = false
            addressPathTemplate = nil
            addressPageStart = addressStartIndex
            navigate(to: .addresses)
        default:
            return false
        }
        return true
    }

    func confirmMultisigStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .enrollImportedMultisig:
            if pendingNFCMultisig != nil { return false }
            commitPendingMultisig()
        case .confirmDeleteMultisig:
            deleteSelectedMultisig()
        case .continueTrustPSBT:
            back()
            openMenu(.trustPSBT)
        case .continueSkipChecks:
            back()
            openMenu(.skipChecks)
        case .continueUnsortedMultisig:
            back()
            openMenu(.unsortedMultisig)
        case .continueExportXPUB:
            back()
            accountPromptPurpose = .multisigXPUB
            accountPromptValue = "0"
            navigate(to: .accountNumber)
        case .continueElectrumExport:
            back()
            exportSelectedMultisig { wallet, xfp in
                Data(try wallet.electrumExport(myFingerprint: xfp).utf8)
            }
        case .addOwnAirgappedKey:
            back()
            accountPromptPurpose = .multisigCreateAccount
            accountPromptValue = "0"
            navigate(to: .accountNumber)
        case .showPendingMultisigXpubs:
            if let wallet = pendingMultisigWallet {
                showStory(title: "", body: wallet.detailText(verbose: false), onConfirm: .enrollImportedMultisig)
            } else {
                back()
            }
        case .importMultisigPrompt:
            back()
            importPurpose = .multisig
            showFileImporter = true
        case .createAirgappedSource:
            if createAirgappedCosigners.isEmpty {
                continueCreateAirgapped(isQR: false)
            } else {
                finishCreateAirgappedCollection()
            }
        case .createAirgappedFormat:
            finishCreateAirgappedFormat(.p2wsh)
        case .exportPrettyDescriptor:
            back()
            pendingMultisigPrettyExport = true
            exportSelectedMultisig { wallet, _ in Data(try wallet.prettyDescriptor().utf8) }
        default:
            return false
        }
        return true
    }

    func handleMultisigStoryKey(_ value: String) -> Bool {
        let key = value.lowercased()
        switch story.onConfirm {
        case .enrollImportedMultisig:
            if pendingNFCMultisig != nil { return false }
            if key == "1" {
                story.onConfirm = .showPendingMultisigXpubs
                confirmStory()
                return true
            }
        case .exportPrettyDescriptor:
            if key == "1" {
                confirmStory()
                return true
            }
        case .importMultisigPrompt:
            if key == "1" {
                importPurpose = .multisig
                showFileImporter = true
                return true
            }
            if key == "b" {
                importMultisigFromCard(slotB: true)
                return true
            }
            if key == "2" {
                importMultisigFromCard(slotB: false, virtDisk: true)
                return true
            }
        case .createAirgappedSource:
            if key == "1" || value == "\r" { return false }
        case .createAirgappedFormat:
            if key == "1" {
                finishCreateAirgappedFormat(.p2shP2wsh)
                return true
            }
        default:
            break
        }
        return false
    }

    func beginMultisigImport() {
        let prompt = FirmwareImportPrompt.qImportPrompt(
            title: "multisig wallet file",
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: preferences.nfcSharingEnabled
        )
        showStory(title: "", body: prompt, onConfirm: .importMultisigPrompt,
                  hintQR: true, hintNFC: preferences.nfcSharingEnabled)
    }

    func importMultisigFromText(_ text: String, nameHint: String? = nil) {
        beginWorking(.wait)
        let existing = preferences.importedMultisigWallets
        let unsorted = preferences.allowUnsortedMultisig
        let skip = skipMultisigChecks
        guard let root = rootKey else {
            endWorking()
            showStory(title: "", body: FirmwareCopy.needSeedForMultisig)
            return
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (ImportedMultisigWallet?, String?) in
                do {
                    let context = MultisigImportContext(root: root, allowUnsorted: unsorted, disableChecks: skip)
                    return (try MultisigWalletConfig.importFile(text, nameHint: nameHint, context: context), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            endWorking()
            if let wallet = result.0 {
                offerEnroll(wallet, existing: existing)
            } else {
                showStory(title: "Failure", body: "Failed to import multisig.\n\n\(result.1 ?? "")")
            }
        }
    }

    func importMultisigFromQR() {
        importPurpose = .multisig
        showScanner = true
    }

    func importMultisigFromNFC() {
        guard preferences.nfcSharingEnabled else {
            showStory(title: "", body: FirmwareCopy.nfcRequiredToEnable, onConfirm: .enableNFCForFeature)
            return
        }
        SimulatorNFC.read(prompt: "Hold a tag with a multisig config") { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    if let nfc = error as? SimulatorNFCError {
                        switch nfc {
                        case .unavailable: self.beginMultisigImport()
                        case .cancelled: return
                        case .failed(let message):
                            self.showStory(title: "ERROR", body: "Failed to import multisig. \(message)")
                        }
                    } else {
                        self.showStory(title: "ERROR", body: "Failed to import multisig. \(error.localizedDescription)")
                    }
                case .success(let payloads):
                    let text = payloads.compactMap { String(data: $0, encoding: .utf8) }
                        .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    if let text {
                        self.importMultisigFromText(text)
                    } else {
                        self.showStory(title: "", body: FirmwareCopy.nfcMultisigMissing)
                    }
                }
            }
        }
    }

    func importMultisigFromCard(slotB: Bool, virtDisk: Bool = false) {
        let volume: SimulatorCardStandin.Volume = virtDisk ? .virtDisk : .microSD
        let files = SimulatorCardStandin.listRootFiles(on: volume, minSize: 100, maxSize: 20 * 200)
            .filter { file in
                let lower = file.filename.lowercased()
                guard lower.hasSuffix(".txt") || lower.hasSuffix(".json") else { return false }
                guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { return false }
                return text.contains("pub") || text.contains("sh(") || text.contains("wsh(")
            }
        if files.isEmpty {
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        if files.count == 1, let file = files.first, let text = try? String(contentsOf: file.url, encoding: .utf8) {
            importMultisigFromText(text, nameHint: (file.filename as NSString).deletingPathExtension)
            return
        }
        importPurpose = .multisig
        showFileImporter = true
    }

    func offerEnroll(_ wallet: ImportedMultisigWallet, existing: [ImportedMultisigWallet]) {
        pendingMultisigWallet = wallet
        let confirm = wallet.confirmImportStory(existing: existing)
        if confirm.isDuplicate {
            showStory(title: "", body: confirm.body)
            return
        }
        showStory(title: "", body: confirm.body, onConfirm: .enrollImportedMultisig)
    }

    func commitPendingMultisig() {
        guard var wallet = pendingMultisigWallet else {
            back()
            return
        }
        let names = preferences.importedMultisigWallets.map(\.name)
        wallet.name = MultisigWalletConfig.uniqueName(wallet.name, existing: names)
        var wallets = preferences.importedMultisigWallets
        wallets.append(wallet)
        persistMultisigWallets(wallets)
        pendingMultisigWallet = nil
        back()
        if currentPSBT != nil {
            statusMessage = "Saved."
            return
        }
        statusMessage = "Saved."
    }

    func showSelectedMultisigDetail() {
        guard let wallet = selectedMultisig else { return }
        beginWorking(.wait)
        let text = wallet.detailText(verbose: true)
        endWorking()
        showStory(title: "", body: text)
    }

    func beginRenameMultisig() {
        guard let wallet = selectedMultisig else { return }
        renamingMultisigIndex = selectedMultisigIndex
        passphraseInput = wallet.name
        navigate(to: .passphrase)
    }

    func saveMultisigRename() {
        guard let index = renamingMultisigIndex,
              preferences.importedMultisigWallets.indices.contains(index) else { return }
        let name = String(passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
        renamingMultisigIndex = nil
        passphraseInput = ""
        back()
        guard !name.isEmpty else { return }
        if name == preferences.importedMultisigWallets[index].name { return }
        if preferences.importedMultisigWallets.contains(where: { $0.name == name }) {
            showStory(title: "", body: "Name in use.")
            return
        }
        preferences.importedMultisigWallets[index].name = name
        persistPreferencesQuietly()
        if screen == .menu, currentMenu == .multisigWallet {
            back()
        }
    }

    func deleteSelectedMultisig() {
        guard let index = selectedMultisigIndex,
              preferences.importedMultisigWallets.indices.contains(index) else {
            back()
            return
        }
        var wallets = preferences.importedMultisigWallets
        wallets.remove(at: index)
        persistMultisigWallets(wallets)
        selectedMultisigIndex = nil
        back()
        if screen == .menu, currentMenu == .multisigWallet {
            back()
        }
        statusMessage = "Deleted."
    }

    func showSelectedMultisigDescriptor() {
        guard let wallet = selectedMultisig else { return }
        beginWorking(.wait)
        do {
            let body = "Press (1) to export in pretty human readable format.\n\n" + (try wallet.descriptor())
            endWorking()
            showStory(title: "", body: body, onConfirm: .exportPrettyDescriptor)
        } catch {
            endWorking()
            present(error)
        }
    }

    func exportSelectedMultisig(_ builder: @escaping (ImportedMultisigWallet, String) throws -> Data) {
        guard let wallet = selectedMultisig, let xfp = rootKey?.fingerprintHex else { return }
        let pretty = pendingMultisigPrettyExport
        pendingMultisigPrettyExport = false
        presentGeneratedExport(title: wallet.name, filename: wallet.makeFilename(prefix: pretty ? "desc" : "ms")) {
            if pretty { return Data(try wallet.prettyDescriptor().utf8) }
            return try builder(wallet, xfp)
        }
    }

    func exportMultisigXPUB(account: UInt32) {
        guard let root = rootKey else { return }
        let xfp = root.fingerprintHex.lowercased()
        presentGeneratedExport(title: "Multisig XPUB", filename: "ccxp-\(xfp).json") {
            Data(try MultisigXPUBExport.json(root: root, account: account).utf8)
        }
    }

    private func presentGeneratedExport(title: String, filename: String, builder: @escaping () throws -> Data) {
        beginWorking(.generating)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do { return (try builder(), nil) }
                catch { return (nil, error.localizedDescription) }
            }.value
            endWorking()
            if let data = result.0 {
                exportContents(title: title, filename: filename, text: String(decoding: data, as: UTF8.self))
            } else {
                errorMessage = result.1
            }
        }
    }

    func beginCreateAirgapped() {
        showStory(title: "QR or SD Card?",
                  body: "Press QR to scan multisg XPUBs from QR codes (BBQr) or ENTER to use SD card(s).",
                  onConfirm: .createAirgappedSource, hintQR: true)
    }

    func continueCreateAirgapped(isQR: Bool) {
        createAirgappedQR = isQR
        if isQR {
            showStory(title: "Address Format",
                      body: "Press ENTER for default address format (P2WSH, segwit), otherwise, press (1) for P2SH-P2WSH.",
                      onConfirm: .createAirgappedFormat)
        } else {
            showStory(title: "",
                      body: FirmwareCopy.createAirgappedSD,
                      onConfirm: .createAirgappedFormat)
        }
    }

    func finishCreateAirgappedFormat(_ format: MultisigAddressFormat) {
        createAirgappedFormat = format
        createAirgappedCosigners = []
        createAirgappedMineCount = 0
        if createAirgappedQR {
            importPurpose = .multisigCreateXPUB
            showScanner = true
        } else {
            collectCreateAirgappedFromCards()
        }
    }

    func ingestCreateAirgappedJSON(_ text: String, quiet: Bool = false) {
        let key = createAirgappedFormat == .p2shP2wsh ? "p2sh_p2wsh" : "p2wsh"
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            if !quiet { showStory(title: "", body: "Unable to decode JSON data") }
            return
        }
        do {
            let cosigner = try MultisigXPUBExport.cosigner(from: object, addressKey: key)
            if createAirgappedCosigners.contains(where: { $0.fingerprint == cosigner.fingerprint && $0.xpub == cosigner.xpub }) {
                return
            }
            if cosigner.fingerprint.uppercased() == (rootKey?.fingerprintHex ?? "").uppercased() {
                createAirgappedMineCount += 1
            }
            createAirgappedCosigners.append(cosigner)
            if createAirgappedQR {
                showStory(title: "",
                          body: "Number of keys scanned: \(createAirgappedCosigners.count)\n\nENTER when done, QR to scan more.",
                          onConfirm: .createAirgappedSource, hintQR: true)
            }
        } catch {
            if !quiet { showStory(title: "", body: "Failure: \(error.localizedDescription)") }
        }
    }

    func collectCreateAirgappedFromCards() {
        var volumes: [SimulatorCardStandin.Volume] = [.microSD]
        if virtualDiskEnabled { volumes.append(.virtDisk) }
        for volume in volumes {
            for file in SimulatorCardStandin.listRootFiles(on: volume, minSize: 0, maxSize: 1100) {
                let name = file.filename.lowercased()
                guard name.hasPrefix("ccxp-"), name.hasSuffix(".json") else { continue }
                guard let text = try? String(contentsOf: file.url, encoding: .utf8) else { continue }
                ingestCreateAirgappedJSON(text, quiet: true)
            }
        }
        finishCreateAirgappedCollection()
    }

    func finishCreateAirgappedCollection() {
        let xpubs = createAirgappedCosigners
        let mine = createAirgappedMineCount
        if xpubs.isEmpty || (xpubs.count == 1 && mine > 0) {
            let msg = createAirgappedQR
                ? "No XPUBs scanned. Exit."
                : "Unable to find any Coldcard exported keys on this card. Must have filename: ccxp-....json"
            showStory(title: "", body: msg)
            return
        }
        if mine == 0, let xfp = rootKey?.fingerprintHex {
            showStory(title: "[\(xfp)]",
                      body: "Add current Coldcard with above XFP ?",
                      onConfirm: .addOwnAirgappedKey)
            return
        }
        promptCreateAirgappedM()
    }

    func addOwnAirgappedKey(account: UInt32) {
        guard let root = rootKey else { return }
        do {
            let json = try MultisigXPUBExport.json(root: root, account: account)
            let key = createAirgappedFormat == .p2shP2wsh ? "p2sh_p2wsh" : "p2wsh"
            guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
            let cosigner = try MultisigXPUBExport.cosigner(from: object, addressKey: key)
            createAirgappedCosigners.append(cosigner)
            createAirgappedMineCount += 1
            promptCreateAirgappedM()
        } catch {
            showStory(title: "ERROR", body: "Failed to create multisig.\n\n\(error.localizedDescription)")
        }
    }

    func promptCreateAirgappedM() {
        let n = createAirgappedCosigners.count
        if n < 2 || n > maxMultisigSigners {
            showStory(title: "", body: "Invalid number of signers,min is 2 max is \(maxMultisigSigners).")
            return
        }
        accountPromptPurpose = .multisigCreateM
        accountPromptValue = String(n)
        navigate(to: .accountNumber)
    }

    func completeCreateAirgapped(mValue: UInt32) {
        let n = createAirgappedCosigners.count
        let m = Int(mValue)
        guard (1...n).contains(m) else {
            showStory(title: "", body: "Invalid number of signers,min is 2 max is \(maxMultisigSigners).")
            return
        }
        guard let root = rootKey else { return }
        let name = MultisigWalletConfig.uniqueName(
            "CC-\(m)-of-\(n)",
            existing: preferences.importedMultisigWallets.map(\.name)
        )
        var lines = [
            "Name: \(name)",
            "Policy: \(m) of \(n)",
            "Format: \(createAirgappedFormat.exportLabel)"
        ]
        var last: String?
        for cosigner in createAirgappedCosigners {
            if last != cosigner.derivation {
                lines.append("")
                lines.append("Derivation: \(cosigner.derivation)")
                lines.append("")
                last = cosigner.derivation
            }
            lines.append("\(cosigner.fingerprint): \(cosigner.xpub)")
        }
        do {
            let context = MultisigImportContext(root: root,
                                                allowUnsorted: preferences.allowUnsortedMultisig,
                                                disableChecks: skipMultisigChecks)
            let wallet = try MultisigWalletConfig.importFile(lines.joined(separator: "\n"),
                                                             nameHint: name, context: context)
            if createAirgappedMineCount == 0 {
                exportContents(title: name, filename: wallet.makeFilename(prefix: "ms"),
                               text: try wallet.descriptor())
                return
            }
            offerEnroll(wallet, existing: preferences.importedMultisigWallets)
        } catch {
            showStory(title: "ERROR", body: "Failed to create multisig.\n\n\(error.localizedDescription)")
        }
    }

    func exportContents(title: String, filename: String, text: String) {
        walletExportTitle = title
        walletExportText = text
        exportFilename = filename
        navigate(to: .walletExport)
    }

    func loadMultisigAddresses() {
        guard let index = exploringMultisigIndex,
              preferences.importedMultisigWallets.indices.contains(index),
              let root = rootKey else { return }
        let wallet = preferences.importedMultisigWallets[index]
        let start = addressPageStart
        let change: UInt32 = addressChange ? 1 : 0
        let showFull = preferences.fullMultisigAddressView
        beginWorking(.wait)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ([DerivedAddress]?, String?) in
                do {
                    var rows: [DerivedAddress] = []
                    let count = Int(AddressExplorer.visibleCount(start: start))
                    for offset in 0..<count {
                        let idx = start + UInt32(offset)
                        let derived = try wallet.derivedAddress(change: change, index: idx, network: root.network)
                        let shown = MultisigWalletConfig.censorAddress(derived.address, showFull: showFull)
                        let path = AddressExplorer.multisigDerivationLine(
                            idx: idx, change: change, signerCount: wallet.totalSigners, paths: derived.paths
                        )
                        rows.append(DerivedAddress(index: idx, change: change != 0, path: path,
                                                   address: shown, publicKeyHex: "",
                                                   scriptPubKeyHex: derived.scriptPubKeyHex))
                    }
                    return (rows, nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            endWorking()
            if let rows = result.0 {
                derivedAddresses = rows
                storyTop = 0
            } else {
                errorMessage = result.1 ?? "Unable to derive addresses."
            }
        }
    }

    func applyMultisigToPSBT(_ psbt: PSBT, root: HDKey) -> (wallets: [ImportedMultisigWallet], enroll: ImportedMultisigWallet?) {
        let wallets = preferences.importedMultisigWallets
        if skipMultisigChecks { return (wallets, nil) }
        guard !psbt.globalXpubs.isEmpty else { return (wallets, nil) }
        if psbt.review(root: root, wallets: wallets).multisigWalletName != nil {
            return (wallets, nil)
        }
        guard let built = try? walletFromPSBT(psbt, root: root) else { return (wallets, nil) }
        switch effectiveMultisigTrustPolicy {
        case 0:
            return (wallets, nil)
        case 2:
            return (wallets + [built], nil)
        default:
            return (wallets, built)
        }
    }

    func walletFromPSBT(_ psbt: PSBT, root: HDKey) throws -> ImportedMultisigWallet {
        var format: MultisigAddressFormat = .p2wsh
        var required = 0
        var total = 0
        for index in psbt.inputs.indices {
            let redeem = psbt.inputs[index].first(type: 0x04)?.value ?? psbt.inputs[index].first(type: 0x05)?.value
            if let redeem, let parsed = try? MultisigScript.disassemble(redeem) {
                required = parsed.requiredSignatures
                total = parsed.totalSigners
                if let utxo = try? psbt.resolvedUTXOForMultisig(index: index) {
                    if utxo.scriptPubKey.first == 0xa9 { format = .p2shP2wsh }
                    else if utxo.scriptPubKey.first == 0x00 { format = .p2wsh }
                    else { format = .p2sh }
                }
                break
            }
        }
        if total == 0 { total = psbt.globalXpubs.count }
        if required == 0 { required = total }
        var lines = [
            "Name: PSBT-\(required)-of-\(total)",
            "Policy: \(required) of \(total)",
            "Format: \(format.exportLabel)"
        ]
        var last: String?
        for item in psbt.globalXpubs {
            let node = try HDKey.parseExtendedKeyData(item.extendedKey, network: root.network)
            let xpub = node.serializePublic()
            let fp = item.fingerprint.hexString.uppercased()
            let deriv = item.path.description
            if last != deriv {
                lines.append("")
                lines.append("Derivation: \(deriv)")
                lines.append("")
                last = deriv
            }
            lines.append("\(fp): \(xpub)")
        }
        let context = MultisigImportContext(root: root,
                                            allowUnsorted: preferences.allowUnsortedMultisig,
                                            disableChecks: true)
        return try MultisigWalletConfig.importFile(lines.joined(separator: "\n"),
                                                   nameHint: "PSBT-\(required)-of-\(total)",
                                                   context: context)
    }

    func handleMultisigQRKey() -> Bool {
        if screen == .menu, currentMenu == .multisigWallets {
            importMultisigFromQR()
            return true
        }
        switch story.onConfirm {
        case .importMultisigPrompt:
            importMultisigFromQR()
            return true
        case .createAirgappedSource:
            if createAirgappedCosigners.isEmpty {
                continueCreateAirgapped(isQR: true)
            } else {
                importPurpose = .multisigCreateXPUB
                showScanner = true
            }
            return true
        default:
            return false
        }
    }

    func handleMultisigNFCKey() -> Bool {
        if screen == .menu, currentMenu == .multisigWallets {
            importMultisigFromNFC()
            return true
        }
        if story.onConfirm == .importMultisigPrompt {
            importMultisigFromNFC()
            return true
        }
        return false
    }
}

private extension PSBT {
    func resolvedUTXOForMultisig(index: Int) throws -> TransactionOutput {
        let map = inputs[index]
        if let nonWitness = map.first(type: 0x00) {
            let previous = try BitcoinTransaction(data: nonWitness.value)
            let input = unsignedTransaction.inputs[index]
            guard Int(input.previousOutputIndex) < previous.outputs.count else { throw PSBTError.invalidUTXO }
            return previous.outputs[Int(input.previousOutputIndex)]
        }
        if let witness = map.first(type: 0x01) { return try TransactionOutput.parse(witness.value) }
        throw PSBTError.invalidUTXO
    }
}
