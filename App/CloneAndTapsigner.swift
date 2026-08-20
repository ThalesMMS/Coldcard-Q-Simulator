import Foundation
import UniformTypeIdentifiers
import ColdcardCore

extension SimulatorStore {
    static func normalizedHexEntry(_ text: String) -> String {
        String(text.filter(\.isHexDigit).prefix(32)).lowercased()
    }

    static func rootKey(fromBackup payload: WalletBackupPayload) throws -> HDKey {
        let mnemonic = payload.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mnemonic.isEmpty {
            return try HDKey(seed: BIP39Mnemonic(phrase: mnemonic).seed(), network: payload.network)
        }
        if let xprv = payload.extendedPrivateKey, !xprv.isEmpty {
            return try hdKey(fromExtendedPrivate: xprv, network: payload.network)
        }
        throw SimulatorInputError.missingSeed
    }

    func handleCloneTapsignerStoryKey(_ value: String) -> Bool {
        switch story.onConfirm {
        case .tapsignerImportSource:
            if value == "1" || value == "b" {
                pickTapsignerBackupFile()
                return true
            }
            if value == "2" {
                importTapsignerFromVirtualDisk()
                return true
            }
            return false
        default:
            return false
        }
    }

    func consumeTapsignerNFCKey() -> Bool {
        guard screen == .story, story.onConfirm == .tapsignerImportSource else { return false }
        importTapsignerFromNFC()
        return true
    }

    // MARK: - D039 Migrate / clone ingest (`clone_start`)

    func startCloneIngest() {
        if hasSeed, !pendingEphemeral, !restoreAsEphemeral {
            showStory(title: "Migrate Coldcard", body: FirmwareCopy.needClearSeed)
            return
        }
        cloneIngestTriedCard = false
        showStory(title: "", body: FirmwareCopy.cloneStartInsert, onConfirm: .cloneStartWriteKey)
    }

    func writeCloneStartFile() {
        back()
        do {
            let pair = try generateCloneKeypair()
            cloneSessionPrivateKey = pair.privateKey
            let data = try CloneTransfer.startFile(compressedPubkey: pair.publicKey)
            _ = try writeCardStandin(data, named: CloneTransfer.startFilename, to: .microSD)
            pendingCloneIngestAfterExport = true
            cloneIngestTriedCard = false
            prepareExport(data: data, filename: CloneTransfer.startFilename, type: .json)
        } catch {
            abortCloneIngest()
            present(error)
        }
    }

    func continueCloneIngest() {
        if let incoming = firstCloneBackupOnCard() {
            ingestCloneBackup(data: incoming.data, filename: incoming.filename)
            return
        }
        if cloneIngestTriedCard {
            importPurpose = .cloneIngest
            showFileImporter = true
            return
        }
        cloneIngestTriedCard = true
        showStory(title: "", body: FirmwareCopy.cloneFileNotFound, onConfirm: .cloneIngestPickFile)
    }

    func ingestCloneBackup(data: Data, filename: String) {
        guard let session = cloneSessionPrivateKey else {
            errorMessage = "Clone session expired. Start Migrate Coldcard again."
            return
        }
        do {
            let (envelope, writerPub) = try cloneEnvelope(data: data, filename: filename)
            let password = try CloneTransfer.sessionPasswordHex(privateKey: session, theirPubkey: writerPub)
            beginWorking(.loading)
            Task {
                let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                    do {
                        let clear = try BackupCrypto.decryptBytes(envelope, password: password)
                        return (clear, nil)
                    } catch SecureServiceError.wrongPassword {
                        return (nil, BackupFile.decryptFailed(tried: password))
                    } catch {
                        return (nil, error.localizedDescription)
                    }
                }.value
                endWorking()
                if let clear = result.0 {
                    do {
                        let payload = try SimulatorStore.payloadFromClearBytes(clear)
                        removeCloneSessionFiles()
                        cloneSessionPrivateKey = nil
                        cloneIngestTriedCard = false
                        pendingRestorePayload = payload
                        restoreAsEphemeral = false
                        pendingEphemeral = false
                        let key = try Self.rootKey(fromBackup: payload)
                        showStory(title: "[\(key.fingerprintHex)]",
                                  body: FirmwareCopy.restoreBackupAsMaster,
                                  onConfirm: .confirmRestoreBackup)
                    } catch { present(error) }
                } else {
                    showStory(title: "FAILED", body: result.1 ?? "Unable to open the clone backup.")
                }
            }
        } catch {
            showStory(title: "FAILED", body: error.localizedDescription)
        }
    }

    func abortCloneIngest() {
        cloneSessionPrivateKey = nil
        cloneIngestTriedCard = false
        pendingCloneIngestAfterExport = false
        let start = SimulatorCardStandin.directory(for: .microSD)
            .appendingPathComponent(CloneTransfer.startFilename)
        try? FileManager.default.removeItem(at: start)
    }

    // MARK: - D050 Clone Coldcard write (`clone_write_data`)

    func startCloneWrite() {
        guard record != nil, hasSeed || tmpSeedActive else {
            showStory(title: "", body: FirmwareCopy.cloneWriteNeedStart, onConfirm: .cloneWritePickStart)
            return
        }
        if let data = microSDFileData(named: CloneTransfer.startFilename),
           let pubkey = try? CloneTransfer.parseStartFile(data) {
            clonePeerPubkey = pubkey
            confirmCloneWriteIfNeeded()
            return
        }
        showStory(title: "", body: FirmwareCopy.cloneWriteNeedStart, onConfirm: .cloneWritePickStart)
    }

    func pickCloneStartFile() {
        importPurpose = .cloneStartFile
        showFileImporter = true
    }

    func ingestCloneStartFile(data: Data) {
        do {
            clonePeerPubkey = try CloneTransfer.parseStartFile(data)
            confirmCloneWriteIfNeeded()
        } catch {
            showStory(title: "FAILED", body: error.localizedDescription)
        }
    }

    func writeCloneBackup() {
        guard record != nil, let theirPub = clonePeerPubkey else {
            showStory(title: "", body: FirmwareCopy.cloneWriteNeedStart, onConfirm: .cloneWritePickStart)
            return
        }
        guard hasSeed || tmpSeedActive else {
            errorMessage = "No seed is in effect to clone."
            return
        }
        if screen == .story { back() }
        do {
            let body = try currentBackupText()
            let pair = try generateCloneKeypair()
            let password = try CloneTransfer.sessionPasswordHex(privateKey: pair.privateKey, theirPubkey: theirPub)
            beginWorking(.saving)
            Task {
                let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?, String?) in
                    do {
                        let envelope = try BackupCrypto.encryptBytes(Data(body.utf8), password: password, innerExt: "txt")
                        return (envelope, CloneTransfer.cloneFilename(compressedPubkey: pair.publicKey), nil)
                    } catch {
                        return (nil, nil, error.localizedDescription)
                    }
                }.value
                endWorking()
                guard let data = result.0, let filename = result.1 else {
                    errorMessage = result.2
                    return
                }
                removeCloneBackupFiles()
                do {
                    _ = try writeCardStandin(data, named: filename, to: .microSD)
                    prepareExport(data: data, filename: filename, type: .sevenZip,
                                  successStory: ("", FirmwareCopy.cloneWriteDone))
                } catch { present(error) }
            }
        } catch { present(error) }
    }

    // MARK: - D040 TAPSIGNER backup import

    func startTapsignerBackupImport() {
        let ephemeral = currentMenu == .temporarySeed || currentMenu == .temporarySeedImport || pendingEphemeral
        pendingEphemeral = ephemeral
        if !ephemeral, hasSeed {
            showStory(title: "Tapsigner Backup", body: FirmwareCopy.needClearSeed)
            return
        }
        importPurpose = .tapsigner
        pendingTapsignerCiphertext = nil
        pendingTapsignerOrigin = ""
        showStory(title: "",
                  body: FirmwareCopy.tapsignerImportPrompt(virtualDiskEnabled: virtualDiskEnabled,
                                                           nfcEnabled: preferences.nfcSharingEnabled),
                  onConfirm: .tapsignerImportSource)
    }

    func pickTapsignerBackupFile() {
        importPurpose = .tapsigner
        showFileImporter = true
    }

    func importTapsignerFromVirtualDisk() {
        guard virtualDiskEnabled else { return }
        let files = SimulatorCardStandin.listRootFiles(on: .virtDisk, minSize: 100, maxSize: 160)
            .filter { $0.filename.lowercased().hasSuffix(".aes") }
        guard let first = files.first else {
            showStory(title: "", body: FirmwareCopy.tapsignerNoAESFile)
            return
        }
        if files.count == 1, let data = try? Data(contentsOf: first.url) {
            acceptTapsignerCiphertext(data, origin: first.filename)
            return
        }
        pickTapsignerBackupFile()
    }

    func importTapsignerFromNFC() {
        Task {
            switch await NFCPSBTImport.read() {
            case .unavailable:
                showStory(title: "", body: FirmwareCopy.tapsignerNFCUnavailable)
            case .empty:
                showStory(title: "Sorry!", body: FirmwareCopy.nfcNoTagData)
            case .cancelled:
                break
            case .payload(let data):
                if let text = String(data: data, encoding: .utf8),
                   let decoded = try? TapsignerBackup.payload(fromQR: text) {
                    acceptTapsignerCiphertext(decoded, origin: "NFC")
                } else {
                    acceptTapsignerCiphertext(data, origin: "NFC")
                }
            }
        }
    }

    func acceptTapsignerCiphertext(_ data: Data, origin: String) {
        pendingTapsignerCiphertext = data
        pendingTapsignerOrigin = origin
        showStory(title: "", body: FirmwareCopy.tapsignerHaveCard, onConfirm: .tapsignerHaveCard)
    }

    func beginTapsignerKeyEntry() {
        hexEntryText = ""
        navigate(to: .hexEntry)
    }

    func confirmHexEntry() {
        guard hexEntryText.count == 32, let ciphertext = pendingTapsignerCiphertext else { return }
        do {
            let backup = try TapsignerBackup.decrypt(backupKeyHex: hexEntryText, data: ciphertext)
            let origin = pendingTapsignerOrigin.isEmpty ? "from " : "from (\(pendingTapsignerOrigin))"
            pendingTapsignerCiphertext = nil
            pendingTapsignerOrigin = ""
            hexEntryText = ""
            ephemeralOrigin = origin
            importExtendedKey(backup.extendedPrivateKey, temporary: pendingEphemeral)
        } catch {
            showStory(title: "FAILURE", body: error.localizedDescription, onConfirm: .tapsignerRetryKey)
        }
    }

    // MARK: - Internals

    private func confirmCloneWriteIfNeeded() {
        if tmpSeedActive {
            showStory(title: "",
                      body: FirmwareCopy.cloneTmpInEffect(what: "clone",
                                                          passphraseActive: !activePassphrase.isEmpty),
                      onConfirm: .cloneWriteConfirmTmp)
        } else {
            writeCloneBackup()
        }
    }

    private func generateCloneKeypair() throws -> (privateKey: Data, publicKey: Data) {
        for _ in 0..<16 {
            let privateKey = try SecureRandom.bytes(count: 32)
            guard Secp256k1.privateKeyIsValid(privateKey) else { continue }
            let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey, compressed: true)
            return (privateKey, publicKey)
        }
        throw Secp256k1Error.invalidPrivateKey
    }

    private func cloneEnvelope(data: Data, filename: String) throws -> (Data, Data) {
        if let package = try? JSONDecoder().decode(SimulatorClonePackage.self, from: data),
           package.format == "coldcard-q-swift-simulator-clone/1" {
            let pub = try Data(hex: package.writerPubkeyHex)
            return (package.encryptedBackup, pub)
        }
        let pub = try CloneTransfer.parseCloneFilename(filename)
        return (data, pub)
    }

    private func firstCloneBackupOnCard() -> (data: Data, filename: String)? {
        for file in cloneBackupFilesOnCard() {
            if let data = try? Data(contentsOf: file.url) {
                return (data, file.filename)
            }
        }
        return nil
    }

    private func cloneBackupFilesOnCard() -> [ListedDiskFile] {
        SimulatorCardStandin.listRootFiles(on: .microSD).filter { file in
            let lower = file.filename.lowercased()
            return lower.hasSuffix(CloneTransfer.cloneSuffixJSON) || lower.hasSuffix(CloneTransfer.cloneSuffix7z)
        }
    }

    private func microSDFileData(named filename: String) -> Data? {
        let url = SimulatorCardStandin.directory(for: .microSD).appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    private func removeCloneBackupFiles() {
        for file in cloneBackupFilesOnCard() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    private func removeCloneSessionFiles() {
        removeCloneBackupFiles()
        let start = SimulatorCardStandin.directory(for: .microSD)
            .appendingPathComponent(CloneTransfer.startFilename)
        try? FileManager.default.removeItem(at: start)
    }
}
