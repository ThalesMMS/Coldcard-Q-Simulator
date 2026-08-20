import Foundation
import UIKit
import UniformTypeIdentifiers
import ColdcardCore

nonisolated enum TeleportTextKind: Equatable, Sendable {
    case none
    case numericPassword
    case paranoidPassword
    case quickNote
}

nonisolated struct KeyTeleportPendingQR: Equatable, Sendable {
    var fileType: BBQrFileType
    var data: Data
    var cta: String
}

nonisolated struct KeyTeleportCosignerRow: Equatable, Sendable, Identifiable {
    var id: String { fingerprint }
    var fingerprint: String
    var title: String
    var isYou: Bool
    var isDone: Bool
    var canSignNow: Bool
    var canSend: Bool
}

enum KeyTeleportCopy {
    static let reusePubkey = """
    Looks like last attempt wasn't completed. You need to do QR scan of data from the sender to move to the next step. We will re-use same values as last try, unless you press (R) for new values to be picked.
    """
    static func receiveIntro(code: String) -> String {
        """
        To receive sensitive data from another COLDCARD, share this Receiver Password with sender:

           \(code)  =  \(KeyTeleport.grouped(code))

        and show the QR on next screen to the sender. ENTER or QR to show here
        """
    }
    static let receiveIntroNFC = " or NFC to view on your phone"
    static let sendWarning = """
    You can now Key Teleport secrets! Choose what to share on next screen.

    WARNING: Receiver will have full access to all Bitcoin controlled by these keys!
    """
    static func txPassword(label: String, password: String) -> String {
        """
        Share this password with \(label), via some different channel:

           \(password)  =  \(KeyTeleport.grouped(password))

        ENTER to view QR
        """
    }
    static let incorrectPassword = "Incorrect Teleport Password. You can try again or CANCEL to stop."
    static let notExpecting = "Not expecting any teleports. You need to start over."
    static let noMultisigWallets = "Incoming PSBT requires multisig wallet(s) to be already setup, but you have none."
    static let teleportFail = "QR code was damaged, numeric password was wrong, or it was sent to a different user. Sender must start again."
    static let teleportFailPSBT = "QR code was damaged, or it was sent to a different user. Sender must start again."
    static let hobbledOnlyPSBT = "Only PSBT for multisig accepted in this mode."
    static let notPartOfWallet = "We are not part of this multisig wallet."
    static let cannotTeleportTitle = "Cannot Teleport PSBT"
    static let psbtLoadFailed = "PSBT Load Failed"
    static let noMoreSigners = "No more signers?"
    static let failedTitle = "FAILED"
    static let teleportFailTitle = "Teleport Fail"
    static let numericPrompt = "Teleport Password (number)"
    static let paranoidPrompt = "Teleport Password (text)"
    static func paranoidPrompt(from xfp: String) -> String {
        "Teleport Password from [\(xfp)]"
    }
    static let quickNotePrompt = "Enter your message"
    static let quickNotePlaceholder = "Attack at dawn."
    static func shareMaster(scale: String, xfp: String, summary: String) -> String {
        "Sharing \(scale) [\(xfp)] (\(summary)).\n\nWARNING: Allows full control over all associated Bitcoin!"
    }
    static func shareBackup(what: String) -> String {
        "Sending complete backup, including \(what), multisig wallets, notes/passwords, and all settings! The receiving COLDCARD must already have the master seed wiped to be able to install everything, otherwise only the transferred secret and multisig wallets are saved into a temporary seed. OK to proceed?"
    }
    static let offerKT = "Press (T) to use Key Teleport to send PSBT to other co-signers"
    static func pickPSBTPrompt(virtualDiskEnabled: Bool) -> String {
        FirmwareImportPrompt.qImportPrompt(
            title: "PSBT",
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: false,
            includeQR: false
        )
    }
    static let nfcWebTitle = "View QR on web"
    static let nfcStandIn = "Files, Share Sheet, and clipboard stand in for NFC tag emulation. The phone cannot emulate a Coldcard-style tag."
}

extension SimulatorStore {
    var keyTeleportRxKeyHex: String? {
        get { preferences.keyTeleportRxKeyHex }
        set {
            preferences.keyTeleportRxKeyHex = newValue
            persistPreferencesQuietly()
        }
    }

    var canTeleportSignedPSBT: Bool {
        !postSignIsComplete && (signedPSBT ?? currentPSBT)?.globalXpubs.isEmpty == false
    }

    var teleportPassphrasePrompt: String? {
        switch teleportTextKind {
        case .none: nil
        case .numericPassword: KeyTeleportCopy.numericPrompt
        case .paranoidPassword:
            if let xfp = teleportSenderLabel { KeyTeleportCopy.paranoidPrompt(from: xfp) }
            else { KeyTeleportCopy.paranoidPrompt }
        case .quickNote: KeyTeleportCopy.quickNotePrompt
        }
    }

    var storyLCDLines: [LCDStoryLine] {
        LCDStory.compose(title: story.title, body: story.body, hintQR: story.hintQR, hintNFC: story.hintNFC)
    }

    func performKeyTeleportCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .keyTeleportStart:
            startKeyTeleportReceive()
        case .teleportMultisigPSBT:
            startTeleportMultisigPSBT()
        case .keyTeleportQuickNote:
            beginTeleportQuickNote()
        case .keyTeleportPickNote(let id):
            sendTeleportNote(id: id)
        case .keyTeleportExportAllNotes:
            sendTeleportAllNotes()
        case .keyTeleportPickVault(let id):
            sendTeleportVault(id: id)
        case .keyTeleportShareMaster:
            confirmTeleportMaster()
        case .keyTeleportShareBackup:
            confirmTeleportBackup()
        case .keyTeleportPickCosigner(let fingerprint):
            sendTeleportPSBT(to: fingerprint)
        case .keyTeleportSignSelf:
            if let data = teleportPSBTData { loadPSBT(data: data, source: "Key Teleport", inputMethod: "usb") }
        default:
            return false
        }
        return true
    }

    func keyTeleportMenuItems() -> [SimulatorMenuItem]? {
        switch currentMenu {
        case .keyTeleportCosigners: keyTeleportCosignerItems()
        default: nil
        }
    }

    func startKeyTeleportReceive() {
        if let existing = keyTeleportRxKeyHex, !existing.isEmpty {
            showStory(title: "Reuse Pubkey?", body: KeyTeleportCopy.reusePubkey,
                      onConfirm: .keyTeleportReusePubkey, hintQR: true)
            return
        }
        generateKeyTeleportReceiverKey()
        presentKeyTeleportReceiverPassword()
    }

    func generateKeyTeleportReceiverKey() {
        guard let privateKey = try? randomTeleportPrivateKey() else {
            errorMessage = "Unable to pick a Key Teleport key."
            return
        }
        keyTeleportRxKeyHex = privateKey.hexString
    }

    func presentKeyTeleportReceiverPassword() {
        guard let hex = keyTeleportRxKeyHex, let privateKey = try? Data(hex: hex),
              let generated = try? KeyTeleport.generateReceiverCode(privateKey: privateKey) else {
            errorMessage = "Unable to build Receiver Password."
            return
        }
        teleportPendingQR = KeyTeleportPendingQR(fileType: .keyTeleportReceive,
                                                 data: generated.encryptedPubkey,
                                                 cta: "Show to Sender")
        var body = KeyTeleportCopy.receiveIntro(code: generated.numericCode)
        let nfcOK = generated.encryptedPubkey.count < 4096
        if nfcOK { body += KeyTeleportCopy.receiveIntroNFC }
        body += ". CANCEL to stop."
        showStory(title: "Key Teleport: Receive", body: body,
                  onConfirm: .keyTeleportShowPayload, hintQR: true, hintNFC: nfcOK)
    }

    func startKeyTeleportSend(encryptedPubkey: Data) {
        if hobbledMode.isHobbled { return }
        teleportRxEncrypted = encryptedPubkey
        teleportReceiverPubkey = nil
        beginTeleportTextEntry(.numericPassword)
    }

    func startTeleportMultisigPSBT() {
        showStory(title: "Teleport Multisig PSBT",
                  body: KeyTeleportCopy.pickPSBTPrompt(virtualDiskEnabled: virtualDiskEnabled),
                  onConfirm: .keyTeleportPickPSBTFile)
    }

    func beginTeleportPSBTFileImport() {
        importPurpose = .teleportPSBT
        showFileImporter = true
    }

    func importTeleportPSBTFromLowerSlot() {
        let files = SimulatorCardStandin.listRootFiles(on: .microSD, minSize: 50, maxSize: Int.max)
            .filter { $0.filename.lowercased().hasSuffix(".psbt") }
        guard let file = files.first else {
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        importPurpose = .teleportPSBT
        handleImportedFile(file.url)
    }

    func importTeleportPSBTFromVirtualDisk() {
        guard virtualDiskEnabled else { return }
        let files = VirtualDiskFolder.psbtURLs()
        guard let url = files.first else {
            showStory(title: "", body: FirmwareCopy.noSuitableFiles)
            return
        }
        importPurpose = .teleportPSBT
        handleImportedFile(url)
    }

    func handleTeleportPSBTFile(_ data: Data, source: String) {
        let network = self.network
        Task {
            await runReadingProgress(bytes: data.count)
            beginWorking(.validating)
            let parsed: Result<PSBT, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    if data.starts(with: PSBT.magic) { return .success(try PSBT(data: data)) }
                    return .success(try PSBT.decodeText(String(decoding: data, as: UTF8.self)))
                } catch { return .failure(error) }
            }.value
            endWorking()
            switch parsed {
            case .failure(let error):
                showStory(title: KeyTeleportCopy.psbtLoadFailed,
                          body: "Cannot validate PSBT?\n\n\(error.localizedDescription)")
            case .success(let psbt):
                presentTeleportCosigners(psbt: psbt, binary: psbt.serialize(), source: source, network: network)
            }
        }
    }

    func startTeleportFromSignedPSBT() {
        let binary = signedPSBTData ?? currentPSBT?.serialize()
        let psbt = signedPSBT ?? currentPSBT
        guard let binary, let psbt else { return }
        teleportFromSignedPSBT = true
        presentTeleportCosigners(psbt: psbt, binary: binary, source: "signed", network: network)
    }

    func incomingKeyTeleport(fileType: Character, payload: Data) {
        if hobbledMode.isHobbled, fileType != BBQrFileType.keyTeleportPSBT.rawValue { return }
        switch fileType {
        case BBQrFileType.keyTeleportReceive.rawValue:
            startKeyTeleportSend(encryptedPubkey: payload)
        case BBQrFileType.keyTeleportTransmit.rawValue:
            decodeKeyTeleportSender(payload)
        case BBQrFileType.keyTeleportPSBT.rawValue:
            decodeKeyTeleportPSBT(payload)
        default:
            break
        }
    }

    func tryHandleKeyTeleportText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = keyTeleportHashPayload(trimmed) ?? trimmed
        guard payload.hasPrefix(BBQrHeader.prefix), let header = try? BBQrHeader(payload) else { return false }
        switch header.fileType {
        case BBQrFileType.keyTeleportReceive.rawValue,
             BBQrFileType.keyTeleportTransmit.rawValue,
             BBQrFileType.keyTeleportPSBT.rawValue:
            _ = handleBBQrPart(payload)
            return true
        default:
            return false
        }
    }

    func submitTeleportTextEntry() {
        let value = passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = teleportTextKind
        teleportTextKind = .none
        passphraseInput = ""
        back()
        switch kind {
        case .numericPassword:
            completeNumericTeleportPassword(value)
        case .paranoidPassword:
            completeParanoidTeleportPassword(value)
        case .quickNote:
            sendTeleportQuickNote(value)
        case .none:
            break
        }
    }

    func showPendingKeyTeleportQR() {
        guard let pending = teleportPendingQR else { return }
        presentBBQr(title: pending.cta, data: pending.data, fileType: pending.fileType, sensitive: true)
    }

    func sharePendingKeyTeleportNFC() {
        guard let pending = teleportPendingQR else { return }
        let bbqr = KeyTeleport.shortBBQr(fileType: pending.fileType, data: pending.data)
        let url = KeyTeleport.webURL(bbqr: bbqr)
        UIPasteboard.general.string = url
        prepareExport(data: Data(bbqr.utf8),
                      filename: "keyteleport-\(pending.fileType.rawValue).txt",
                      type: .plainText,
                      successStory: (KeyTeleportCopy.nfcWebTitle,
                                     "\(url)\n\n\(KeyTeleportCopy.nfcStandIn)"))
    }

    func confirmKeyTeleportStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .keyTeleportReusePubkey:
            presentKeyTeleportReceiverPassword()
        case .keyTeleportSendWarning:
            openMenu(.keyTeleportSend)
        case .keyTeleportShareMaster:
            sendCurrentSecretViaTeleport()
        case .keyTeleportShareBackup:
            sendFullBackupViaTeleport()
        case .keyTeleportShowPayload:
            showPendingKeyTeleportQR()
            story.onConfirm = .keyTeleportShowPayload
        case .keyTeleportRetryPassword:
            if teleportSessionKey != nil {
                beginTeleportTextEntry(.paranoidPassword)
            } else {
                beginTeleportTextEntry(.numericPassword)
            }
        case .keyTeleportPickPSBTFile:
            beginTeleportPSBTFileImport()
        default:
            return false
        }
        return true
    }

    func handleKeyTeleportQRKey() -> Bool {
        guard screen == .story, story.onConfirm == .keyTeleportShowPayload, teleportPendingQR != nil else {
            return false
        }
        showPendingKeyTeleportQR()
        return true
    }

    func handleKeyTeleportNFCKey() -> Bool {
        guard screen == .story, story.hintNFC, teleportPendingQR != nil else { return false }
        sharePendingKeyTeleportNFC()
        return true
    }

    func handleKeyTeleportStoryKey(_ value: String) -> Bool {
        let key = value.lowercased()
        if story.onConfirm == .keyTeleportReusePubkey, key == "r" {
            generateKeyTeleportReceiverKey()
            presentKeyTeleportReceiverPassword()
            return true
        }
        if story.onConfirm == .keyTeleportPickPSBTFile {
            if key == "1" {
                beginTeleportPSBTFileImport()
                return true
            }
            if key == "b" {
                importTeleportPSBTFromLowerSlot()
                return true
            }
            if key == "2" {
                importTeleportPSBTFromVirtualDisk()
                return true
            }
        }
        return false
    }

    private func keyTeleportCosignerItems() -> [SimulatorMenuItem] {
        teleportCosignerRows.map { row in
            var item = SimulatorMenuItem(id: "kt-cosign-\(row.fingerprint)", title: row.title,
                                         checked: row.isDone,
                                         action: row.canSend ? .command(.keyTeleportPickCosigner(row.fingerprint))
                                            : row.canSignNow ? .command(.keyTeleportSignSelf)
                                            : .command(.menuNoop))
            item.subtitle = nil
            return item
        }
    }

    private func beginTeleportTextEntry(_ kind: TeleportTextKind) {
        teleportTextKind = kind
        passphraseInput = ""
        navigate(to: .passphrase)
    }

    private func completeNumericTeleportPassword(_ code: String) {
        guard let encrypted = teleportRxEncrypted else { return }
        let compact = code.filter(\.isNumber)
        guard compact.count == KeyTeleport.numericCodeLength,
              let pubkey = KeyTeleport.decryptReceiverPubkey(code: compact, payload: encrypted) else {
            showStory(title: "", body: KeyTeleportCopy.incorrectPassword, onConfirm: .keyTeleportRetryPassword)
            return
        }
        teleportReceiverPubkey = pubkey
        showStory(title: "Key Teleport: Send", body: KeyTeleportCopy.sendWarning,
                  onConfirm: .keyTeleportSendWarning)
    }

    private func completeParanoidTeleportPassword(_ password: String) {
        guard let session = teleportSessionKey, let body = teleportWrappedBody else { return }
        do {
            let noid = try KeyTeleport.noidKey(fromPassword: password)
            let plain = try KeyTeleport.decodeStep2(sessionKey: session, noidKey: noid, body: body)
            guard let dtype = plain.first, let ascii = String(bytes: [dtype], encoding: .ascii) else {
                throw KeyTeleportError.truncated
            }
            acceptTeleportedValues(dtype: ascii, raw: Data(plain.dropFirst()))
        } catch {
            showStory(title: "", body: KeyTeleportCopy.incorrectPassword, onConfirm: .keyTeleportRetryPassword)
        }
    }

    private func decodeKeyTeleportSender(_ payload: Data) {
        guard let hex = keyTeleportRxKeyHex, let privateKey = try? Data(hex: hex) else {
            showStory(title: "", body: KeyTeleportCopy.notExpecting)
            startKeyTeleportReceive()
            return
        }
        do {
            let step = try KeyTeleport.decodeStep1(receiverPrivateKey: privateKey, payload: payload)
            teleportSessionKey = step.sessionKey
            teleportWrappedBody = step.body
            teleportSenderLabel = nil
            teleportIsPSBTIncoming = false
            beginTeleportTextEntry(.paranoidPassword)
        } catch {
            showStory(title: KeyTeleportCopy.teleportFailTitle, body: KeyTeleportCopy.teleportFail)
        }
    }

    private func decodeKeyTeleportPSBT(_ payload: Data) {
        guard let root = rootKey else {
            showStory(title: "", body: KeyTeleportCopy.noMultisigWallets)
            return
        }
        let wallets = preferences.importedMultisigWallets
        guard !wallets.isEmpty else {
            showStory(title: "", body: KeyTeleportCopy.noMultisigWallets)
            return
        }
        let myXFP = root.fingerprintHex
        let nonce = payload.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        var found: (session: Data, body: Data, xfp: String)?
        for wallet in wallets {
            guard let mine = wallet.cosigners.first(where: { $0.fingerprint == myXFP }),
                  let myPath = try? DerivationPath(mine.derivation),
                  let priv = try? KeyTeleport.derivedTeleportPrivateKey(root: root, xpubPath: myPath, nonce: nonce)
            else { continue }
            for other in wallet.cosigners where other.fingerprint != myXFP {
                guard let node = try? HDKey.parseExtendedKey(other.xpub, network: network),
                      let pub = try? KeyTeleport.derivedTeleportPubkey(from: node, nonce: nonce),
                      let step = try? KeyTeleport.decodePSBTStep1(receiverPrivateKey: priv,
                                                                  senderPubkey: pub,
                                                                  payload: payload)
                else { continue }
                found = (step.sessionKey, step.body, other.fingerprint)
                break
            }
            if found != nil { break }
        }
        guard let found else {
            showStory(title: KeyTeleportCopy.teleportFailTitle, body: KeyTeleportCopy.teleportFailPSBT)
            return
        }
        teleportSessionKey = found.session
        teleportWrappedBody = found.body
        teleportSenderLabel = found.xfp
        teleportIsPSBTIncoming = true
        beginTeleportTextEntry(.paranoidPassword)
    }

    private func acceptTeleportedValues(dtype: String, raw: Data) {
        if hobbledMode.isHobbled, dtype != "p" {
            showStory(title: KeyTeleportCopy.failedTitle, body: KeyTeleportCopy.hobbledOnlyPSBT)
            return
        }
        switch dtype {
        case "s", "r":
            wipeKeyTeleportRxKey()
            applyTeleportedStash(raw, origin: "Teleported", label: nil)
        case "x":
            wipeKeyTeleportRxKey()
            applyTeleportedXPRVBinary(raw)
        case "n":
            wipeKeyTeleportRxKey()
            importTeleportedNotes(raw)
        case "v":
            wipeKeyTeleportRxKey()
            importTeleportedVault(raw)
        case "p":
            loadPSBT(data: raw, source: "Key Teleport", inputMethod: "usb")
        case "b":
            importTeleportedBackup(raw)
        default:
            showStory(title: KeyTeleportCopy.failedTitle, body: "Unknown teleport type \(dtype).")
        }
    }

    private func applyTeleportedStash(_ raw: Data, origin: String, label: String?, offerVault: Bool = true) {
        do {
            let decoded = try SecretStash.decode(raw)
            switch decoded {
            case .words(let entropy):
                pendingMnemonic = try BIP39Mnemonic(entropy: entropy)
                pendingExtendedKey = nil
            case .xprv(let chain, let priv):
                let key = try HDKey.master(privateKey: priv, chainCode: chain, network: network)
                pendingExtendedKey = try key.serializePrivate()
                pendingMnemonic = nil
            case .masterSecret(let secret):
                guard secret.count == 32 else { throw SecretStashError.invalidLength }
                pendingMnemonic = try BIP39Mnemonic(entropy: secret)
                pendingExtendedKey = nil
            }
            ephemeralOrigin = origin
            if let label { statusMessage = label }
            if hasSeed {
                try applyEphemeralSeed(offerVault: offerVault)
            } else if hasPIN {
                try commitSeedOntoExistingPIN()
            } else {
                beginPINSetup(isChange: false)
            }
        } catch {
            showStory(title: KeyTeleportCopy.failedTitle, body: error.localizedDescription)
        }
    }

    private func applyTeleportedXPRVBinary(_ raw: Data) {
        do {
            let body = raw.count > 78 ? Data(raw.suffix(78)) : raw
            let key = try HDKey.parseExtendedKeyData(body, network: network)
            importExtendedKey(try key.serializePrivate(), temporary: hasSeed)
        } catch {
            showStory(title: KeyTeleportCopy.failedTitle, body: error.localizedDescription)
        }
    }

    private func importTeleportedNotes(_ raw: Data) {
        let wrapped: Data
        if let object = try? JSONSerialization.jsonObject(with: raw),
           JSONSerialization.isValidJSONObject(["coldcard_notes": object]),
           let data = try? JSONSerialization.data(withJSONObject: ["coldcard_notes": object]) {
            wrapped = data
        } else {
            wrapped = raw
        }
        importNotes(data: wrapped)
        openMenu(.notes, remember: false)
        statusMessage = "Imported."
    }

    private func importTeleportedVault(_ raw: Data) {
        guard let array = try? JSONSerialization.jsonObject(with: raw) as? [Any],
              array.count >= 4,
              let xfp = array[0] as? String,
              let encoded = array[1] as? String,
              let label = array[2] as? String,
              let origin = array[3] as? String,
              let stash = try? Data(hex: encoded)
        else {
            showStory(title: KeyTeleportCopy.failedTitle, body: "Invalid vault export.")
            return
        }
        applyTeleportedStash(stash, origin: origin.isEmpty ? "Teleported" : origin, label: label,
                             offerVault: false)
        if preferences.seedVaultEnabled, let phrase = ephemeralPhrase,
           !preferences.vaultedSeeds.contains(where: { $0.mnemonic == phrase }) {
            preferences.vaultedSeeds.append(VaultedSeed(fingerprint: xfp, mnemonic: phrase,
                                                        label: label, origin: origin))
            persistPreferencesQuietly()
        }
    }

    private func importTeleportedBackup(_ raw: Data) {
        wipeKeyTeleportRxKey()
        do {
            let payload = try SimulatorStore.payloadFromClearBytes(raw)
            pendingRestorePayload = payload
            pendingMnemonic = try BIP39Mnemonic(phrase: payload.mnemonic)
            pendingNotes = payload.notes
            if hasSeed {
                ephemeralOrigin = "Coldcard Backup"
                try applyEphemeralSeed()
            } else if hasPIN {
                try commitSeedOntoExistingPIN()
            }
        } catch {
            showStory(title: KeyTeleportCopy.failedTitle, body: "Invalid backup\n\n\(error.localizedDescription)")
        }
    }

    private func beginTeleportQuickNote() {
        beginTeleportTextEntry(.quickNote)
    }

    private func sendTeleportQuickNote(_ text: String) {
        guard !text.isEmpty else { return }
        let record = SecureNote(kind: .note, title: "Quick Note", note: text).firmwareRecord()
        sendTeleportJSON(dtype: "n", object: [record])
    }

    private func sendTeleportNote(id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        sendTeleportJSON(dtype: "n", object: [note.firmwareRecord()])
    }

    private func sendTeleportAllNotes() {
        sendTeleportJSON(dtype: "n", object: notes.map { $0.firmwareRecord() })
    }

    private func sendTeleportVault(id: UUID) {
        guard let seed = preferences.vaultedSeeds.first(where: { $0.id == id }),
              let mnemonic = try? BIP39Mnemonic(phrase: seed.mnemonic) else { return }
        let encoded = SecretStash.encode(entropy: mnemonic.entropy).hexString
        sendTeleportJSON(dtype: "v", object: [seed.fingerprint, encoded, seed.label, seed.origin])
    }

    private func confirmTeleportMaster() {
        guard let stash = try? currentSecretStash(), let xfp = rootKey?.fingerprintHex else { return }
        let scale = tmpSeedActive ? "a temporary secret" : "your MASTER secret"
        let summary = SecretStash.summary(stash.first ?? 0)
        teleportPendingStash = stash
        showStory(title: "", body: KeyTeleportCopy.shareMaster(scale: scale, xfp: xfp, summary: summary),
                  onConfirm: .keyTeleportShareMaster)
    }

    private func sendCurrentSecretViaTeleport() {
        guard let stash = teleportPendingStash ?? (try? currentSecretStash()) else { return }
        sendTeleportBody(dtype: "s", body: stash)
    }

    private func confirmTeleportBackup() {
        let what: String
        if tmpSeedActive {
            what = activePassphrase.isEmpty ? "current active temporary secret" : "BIP-39 Passphrase wallet"
        } else {
            what = "master secret, seed vault (if any)"
        }
        showStory(title: "", body: KeyTeleportCopy.shareBackup(what: what),
                  onConfirm: .keyTeleportShareBackup)
    }

    private func sendFullBackupViaTeleport() {
        do {
            sendTeleportBody(dtype: "b", body: Data(try currentBackupText().utf8))
        } catch {
            showStory(title: KeyTeleportCopy.failedTitle, body: error.localizedDescription)
        }
    }

    private func sendTeleportJSON(dtype: String, object: Any) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            errorMessage = "Unable to encode teleport payload."
            return
        }
        sendTeleportBody(dtype: dtype, body: data)
    }

    private func sendTeleportBody(dtype: String, body: Data, prefix: Data = Data(),
                                  senderPrivateKey: Data? = nil, rxLabel: String = "the receiver") {
        guard let receiver = teleportReceiverPubkey else { return }
        let sender: Data
        do {
            sender = try senderPrivateKey ?? Self.randomTeleportPrivateKey()
        } catch {
            showStory(title: KeyTeleportCopy.failedTitle, body: error.localizedDescription)
            return
        }
        beginWorking(.wait)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, Data?, String?) in
                do {
                    let noid = try SecureRandom.bytes(count: KeyTeleport.noidKeyLength)
                    var clear = Data(dtype.utf8)
                    clear.append(body)
                    let payload = try KeyTeleport.encodePayload(
                        senderPrivateKey: sender,
                        receiverPubkey: receiver,
                        noidKey: noid,
                        body: clear,
                        forPSBT: !prefix.isEmpty,
                        prefix: prefix
                    )
                    return (payload, noid, nil)
                } catch {
                    return (nil, nil, error.localizedDescription)
                }
            }.value
            endWorking()
            guard let payload = result.0, let noid = result.1 else {
                showStory(title: KeyTeleportCopy.failedTitle, body: result.2 ?? "Teleport encode failed.")
                return
            }
            let password = KeyTeleport.noidPassword(from: noid)
            teleportPendingQR = KeyTeleportPendingQR(
                fileType: prefix.isEmpty ? .keyTeleportTransmit : .keyTeleportPSBT,
                data: payload,
                cta: "Show to Receiver"
            )
            let nfcOK = payload.count < 4096
            var msg = KeyTeleportCopy.txPassword(label: rxLabel, password: password)
            if nfcOK { msg += KeyTeleportCopy.receiveIntroNFC }
            msg += ". CANCEL to stop."
            showStory(title: "Teleport Password", body: msg,
                      onConfirm: .keyTeleportShowPayload, hintQR: true, hintNFC: nfcOK)
        }
    }

    private func presentTeleportCosigners(psbt: PSBT, binary: Data, source: String, network: BitcoinNetwork) {
        enrollTeleportWallet(from: psbt, network: network)
        guard let root = rootKey else { return }
        let myXFP = root.fingerprintHex
        let xpubs = psbt.globalXpubs
        let all = xpubs.map { $0.fingerprint.hexString.uppercased() }
        guard all.contains(myXFP) || preferences.importedMultisigWallets.contains(where: {
            $0.cosigners.contains(where: { $0.fingerprint == myXFP })
        }) else {
            showStory(title: KeyTeleportCopy.cannotTeleportTitle, body: KeyTeleportCopy.notPartOfWallet)
            return
        }
        let unsigned = unsignedCosignerFingerprints(in: psbt)
        let labels = all.isEmpty
            ? (preferences.importedMultisigWallets.first(where: {
                $0.cosigners.contains(where: { $0.fingerprint == myXFP })
            })?.cosigners.map(\.fingerprint) ?? [])
            : all
        guard !labels.filter({ unsigned.contains($0) && $0 != myXFP }).isEmpty || unsigned.contains(myXFP) else {
            showStory(title: "", body: KeyTeleportCopy.noMoreSigners)
            return
        }
        teleportPSBTData = binary
        teleportReceiverPubkey = nil
        var rows: [KeyTeleportCosignerRow] = []
        for (index, xfp) in labels.enumerated() {
            let isYou = xfp == myXFP
            let isDone = !unsigned.contains(xfp)
            var title = "[\(xfp)] Co-signer #\(index + 1)"
            if isYou { title += ": YOU" }
            else if isDone { title += ": DONE" }
            rows.append(KeyTeleportCosignerRow(fingerprint: xfp, title: title, isYou: isYou,
                                               isDone: isDone, canSignNow: isYou && unsigned.contains(xfp),
                                               canSend: !isYou && !isDone))
        }
        teleportCosignerRows = rows
        if let receiver = xpubs.first(where: { $0.fingerprint.hexString.uppercased() == myXFP }) {
            teleportMyPSBTPath = receiver.path
        } else if let mine = preferences.importedMultisigWallets
            .flatMap(\.cosigners).first(where: { $0.fingerprint == myXFP }),
                  let path = try? DerivationPath(mine.derivation) {
            teleportMyPSBTPath = path
        }
        teleportPSBTXpubs = xpubs
        _ = source
        openMenu(.keyTeleportCosigners)
        if let next = rows.firstIndex(where: { $0.canSend }) {
            selectedMenuIndex = next
        }
    }

    private func sendTeleportPSBT(to fingerprint: String) {
        guard let root = rootKey, let binary = teleportPSBTData,
              let myPath = teleportMyPSBTPath else { return }
        let target = teleportPSBTXpubs.first(where: { $0.fingerprint.hexString.uppercased() == fingerprint })
        let xpubData = target?.extendedKey
        let xpubString = preferences.importedMultisigWallets.flatMap(\.cosigners)
            .first(where: { $0.fingerprint == fingerprint })?.xpub
        let network = self.network
        beginWorking(.wait)
        Task {
            let prepared: Result<(Data, Data, Data, UInt32), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    let riBytes = try SecureRandom.bytes(count: 4)
                    let ri = riBytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % (1 << 28)
                    let prefix = Data([
                        UInt8((ri >> 24) & 0xff),
                        UInt8((ri >> 16) & 0xff),
                        UInt8((ri >> 8) & 0xff),
                        UInt8(ri & 0xff)
                    ])
                    let node: HDKey
                    if let xpubData {
                        node = try HDKey.parseExtendedKeyData(xpubData, network: network)
                    } else if let xpubString {
                        node = try HDKey.parseExtendedKey(xpubString, network: network)
                    } else {
                        throw KeyTeleportError.invalidPublicKey
                    }
                    let rxPub = try KeyTeleport.derivedTeleportPubkey(from: node, nonce: ri)
                    let sender = try KeyTeleport.derivedTeleportPrivateKey(root: root, xpubPath: myPath, nonce: ri)
                    return .success((prefix, rxPub, sender, ri))
                } catch { return .failure(error) }
            }.value
            endWorking()
            switch prepared {
            case .failure(let error):
                if teleportFromSignedPSBT {
                    noteSignedTeleportResult(success: false, remaining: 0)
                } else {
                    showStory(title: KeyTeleportCopy.failedTitle, body: error.localizedDescription)
                }
            case .success(let parts):
                let psbt = signedPSBT ?? currentPSBT
                let need = psbt.map { unsignedCosignerFingerprints(in: $0).count }
                    ?? teleportCosignerRows.filter(\.canSend).count
                let total = max(teleportCosignerRows.count, 1)
                let required = psbt?.guessMultisigPolicy()?.requiredSignatures ?? max(1, total - need)
                teleportRemainingSigs = DoneSigning.signaturesStillNeeded(
                    required: required, total: total, stillNeededAmongWallet: need
                )
                teleportReceiverPubkey = parts.1
                sendTeleportBody(dtype: "p", body: binary, prefix: parts.0,
                                 senderPrivateKey: parts.2,
                                 rxLabel: "[\(fingerprint)] co-signer")
            }
        }
    }

    private func enrollTeleportWallet(from psbt: PSBT, network: BitcoinNetwork) {
        let xpubs = psbt.globalXpubs
        guard xpubs.count >= 2 else { return }
        let cosigners: [MultisigCosigner] = xpubs.compactMap { entry in
            guard let node = try? HDKey.parseExtendedKeyData(entry.extendedKey, network: network) else { return nil }
            return MultisigCosigner(fingerprint: entry.fingerprint.hexString.uppercased(),
                                    derivation: entry.path.description,
                                    xpub: node.serializePublic())
        }
        guard cosigners.count == xpubs.count else { return }
        let existing = preferences.importedMultisigWallets
        if existing.contains(where: { wallet in
            Set(wallet.cosigners.map(\.fingerprint)) == Set(cosigners.map(\.fingerprint))
        }) { return }
        let name = MultisigWalletConfig.uniqueName("Teleported", existing: existing.map(\.name))
        let wallet = MultisigWalletConfig(name: name, requiredSignatures: 1,
                                          totalSigners: cosigners.count,
                                          addressFormat: .p2wsh, chain: network == .mainnet ? "BTC" : "XTN",
                                          bip67: true, cosigners: cosigners)
        preferences.importedMultisigWallets.append(wallet)
        persistPreferencesQuietly()
    }

    private func unsignedCosignerFingerprints(in psbt: PSBT) -> Set<String> {
        var unsigned = Set<String>()
        for input in psbt.inputs {
            let derivations = input.all(type: 0x06).compactMap { try? PSBTDerivation(entry: $0) }
            let signedPubs = Set(input.all(type: 0x02).map(\.keyData))
            for derivation in derivations where !signedPubs.contains(derivation.publicKey) {
                unsigned.insert(derivation.masterFingerprint.hexString.uppercased())
            }
        }
        return unsigned
    }

    private func currentSecretStash() throws -> Data {
        if let mnemonic = activeMnemonic {
            return SecretStash.encode(entropy: mnemonic.entropy)
        }
        if let xprv = ephemeralXPRV ?? record?.extendedPrivateKey {
            let key = try HDKey.parseExtendedKey(xprv, network: network)
            guard let priv = key.privateKey else { throw KeyTeleportError.invalidPrivateKey }
            return SecretStash.encode(chainCode: key.chainCode, privateKey: priv)
        }
        throw SimulatorInputError.missingSeed
    }

    private func wipeKeyTeleportRxKey() {
        keyTeleportRxKeyHex = nil
    }

    private func randomTeleportPrivateKey() throws -> Data {
        try Self.randomTeleportPrivateKey()
    }

    nonisolated private static func randomTeleportPrivateKey() throws -> Data {
        for _ in 0..<16 {
            let key = try SecureRandom.bytes(count: 32)
            if Secp256k1.privateKeyIsValid(key) { return key }
        }
        throw KeyTeleportError.invalidPrivateKey
    }

    private func keyTeleportHashPayload(_ text: String) -> String? {
        let lower = text.lowercased()
        guard lower.contains("keyteleport.com"), let hashIndex = text.firstIndex(of: "#") else { return nil }
        let payload = String(text[text.index(after: hashIndex)...])
        return payload.hasPrefix(BBQrHeader.prefix) ? payload : nil
    }
}
