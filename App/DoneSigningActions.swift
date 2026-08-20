import Foundation
import UniformTypeIdentifiers
import ColdcardCore

extension SimulatorStore {
    var postSignIsComplete: Bool {
        if psbtReview?.bip322Message != nil { return false }
        return signedPSBT?.isComplete(requiredSignatures: signedPSBT?.guessMultisigPolicy()?.requiredSignatures)
            ?? (finalizedTransaction != nil)
    }

    var postSignNoun: String {
        DoneSigning.noun(isComplete: postSignIsComplete, isBIP322: psbtReview?.bip322Message != nil)
    }

    var postSignTxid: String? {
        postSignIsComplete ? finalizedTransaction?.txid : nil
    }

    /// Firmware `done_signing` export story (intro + `export_prompt_builder`).
    var signedTransactionStory: String {
        let prompt = ExportPromptBuilder.prompt(
            whatItIs: postSignNoun,
            dualSDSlots: true,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: preferences.nfcSharingEnabled,
            qrEnabled: true,
            qwerty: true,
            key6: postSignTxid == nil ? nil : DoneSigning.txidQRHint,
            offerKT: canTeleportSignedPSBT ? DoneSigning.offerKT : nil,
            forcePrompt: true
        ) ?? ""
        let intro = DoneSigning.composeIntro(prior: psbtSignedPriorMessage, txid: postSignTxid)
        if intro.isEmpty { return prompt }
        return intro + "\n\n" + prompt
    }

    func presentDoneSigning(title: String = DoneSigning.signedTitle, firstPass: Bool? = nil) {
        if let firstPass { psbtSignedFirstPass = firstPass }
        psbtSignedTitle = title
        if psbtSignedFirstPass {
            psbtSignedFirstPass = false
            switch psbtInputChannel {
            case .qr:
                navigate(to: .psbtSigned)
                showPSBTQR()
                psbtSignedPriorMessage = DoneSigning.sharedVia(postSignNoun, channel: "QR")
                return
            case .nfc:
                navigate(to: .psbtSigned)
                shareSignedResultNFC()
                return
            case .sd:
                saveSignedResult(to: .microSD, isFirstPass: true)
                return
            case .vdisk:
                saveSignedResult(to: .virtDisk, isFirstPass: true)
                return
            case .kt, .other:
                break
            }
        }
        if screen != .psbtSigned { navigate(to: .psbtSigned) }
    }

    func handleSignedPSBTKey(_ value: String) -> Bool {
        guard screen == .psbtSigned else { return false }
        let key = value.lowercased()
        if key == "1" { saveSignedResult(to: .microSD); return true }
        if key == "b" { saveSignedResult(to: .microSD); return true }
        if key == "2", virtualDiskEnabled { saveSignedResult(to: .virtDisk); return true }
        if key == "6", let txid = postSignTxid {
            qrPresentation = QRPresentation(title: txid, payload: txid, sensitive: false)
            return true
        }
        if key == "t", canTeleportSignedPSBT {
            teleportFromSignedPSBT = true
            startTeleportFromSignedPSBT()
            return true
        }
        return false
    }

    func saveSignedResult(to volume: SimulatorCardStandin.Volume, isFirstPass: Bool = false) {
        SimulatorCardStandin.ensureDirectories()
        let dir = SimulatorCardStandin.directory(for: volume)
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir) || !isDir.boolValue {
            presentSignedWriteProblem(DoneSigning.needCard, isMissingCard: true, volume: volume)
            return
        }
        let complete = postSignIsComplete
        let base = DoneSigning.baseName(from: psbtFileBasename)
        var existing = Set(SimulatorCardStandin.listRootFiles(on: volume).map(\.filename))
        var psbtName: String?
        var txnName: String?
        do {
            if !(complete && preferences.deletePSBTs) {
                let target = DoneSigning.psbtFilename(base: base, isComplete: complete)
                let name = DoneSigning.pickFilename(target, existing: existing)
                let data: Data
                if complete, let signed = signedPSBT {
                    data = signed.serialize()
                } else {
                    data = signedPSBTData ?? currentPSBT?.serialize() ?? Data()
                }
                _ = try writeCardStandin(data, named: name, to: volume)
                existing.insert(name)
                psbtName = name
            }
            if complete, let transaction = finalizedTransaction {
                let target = DoneSigning.txnFilename(
                    base: base, txid: transaction.txid, deleteAfter: preferences.deletePSBTs
                )
                let name = DoneSigning.pickFilename(
                    target, existing: existing, overwrite: preferences.deletePSBTs
                )
                let hex = transaction.serialize().hexString + "\r\n"
                _ = try writeCardStandin(Data(hex.utf8), named: name, to: volume)
                txnName = name
            }
            if preferences.deletePSBTs, let url = psbtSourceURL {
                let file = ListedDiskFile(
                    volume: volume,
                    filename: url.lastPathComponent,
                    size: (try? Data(contentsOf: url).count) ?? 0,
                    url: url
                )
                try? SimulatorCardStandin.securelyDelete(file)
            }
        } catch {
            presentSignedWriteProblem(
                DoneSigning.failedToWrite(error.localizedDescription),
                isMissingCard: false,
                volume: volume
            )
            return
        }
        psbtSignedPriorMessage = DoneSigning.saveStory(psbtFilename: psbtName, txnFilename: txnName)
        psbtSignedTitle = DoneSigning.signedTitle
        if screen != .psbtSigned { navigate(to: .psbtSigned) }
        _ = isFirstPass
    }

    func showPSBTQR() {
        let noun = postSignNoun
        let caption = DoneSigning.qrCaption(txid: postSignTxid, noun: noun)
        if let transaction = finalizedTransaction, postSignIsComplete {
            let serialized = transaction.serialize()
            if DoneSigning.usesPlainHexQR(byteCount: serialized.count) {
                qrPresentation = QRPresentation(
                    title: caption, payload: serialized.hexString.uppercased(), sensitive: false
                )
            } else {
                presentBBQr(title: caption, data: serialized, fileType: .transaction)
            }
            psbtSignedPriorMessage = DoneSigning.sharedVia(noun, channel: "QR")
            return
        }
        guard let data = signedPSBTData ?? currentPSBT?.serialize() else { return }
        if DoneSigning.usesPlainHexQR(byteCount: data.count) {
            qrPresentation = QRPresentation(
                title: caption, payload: data.hexString.uppercased(), sensitive: false
            )
        } else {
            presentBBQr(title: caption, data: data, fileType: .psbt)
        }
        psbtSignedPriorMessage = DoneSigning.sharedVia(noun, channel: "QR")
    }

    func shareSignedResultNFC() {
        guard preferences.nfcSharingEnabled else { return }
        let noun = postSignNoun
        if postSignIsComplete, let transaction = finalizedTransaction {
            let raw = transaction.serialize()
            guard raw.count < NFCShare.maxSize else {
                showStory(title: "", body: FirmwareCopy.nfcTxnTooLarge)
                return
            }
            let txid = transaction.txid
            var records: [SimulatorNDEFMessage.Record] = [
                .text("Signed Transaction: \(txid)")
            ]
            if let hex = try? Data(hex: txid) {
                records.append(.binary(type: "bitcoin.org:txid", data: hex))
            }
            records.append(.binary(type: "bitcoin.org:sha256", data: SHA2.sha256(raw)))
            records.append(.binary(type: "bitcoin.org:txn", data: raw))
            writeSignedNFC(SimulatorNDEFMessage(records: records), noun: noun)
            return
        }
        guard let data = signedPSBTData ?? currentPSBT?.serialize() else { return }
        guard data.count < NFCShare.maxSize else {
            showStory(title: "", body: FirmwareCopy.nfcPSBTTooLarge)
            return
        }
        let message = SimulatorNDEFMessage(records: [
            .text("Partly signed PSBT"),
            .binary(type: "bitcoin.org:sha256", data: SHA2.sha256(data)),
            .binary(type: "bitcoin.org:psbt", data: data)
        ])
        writeSignedNFC(message, noun: noun)
    }

    func startBatchSignFromMenu() {
        let body = FirmwareImportPrompt.qImportPrompt(
            title: "PSBTs",
            slotBOnly: false,
            virtualDiskEnabled: virtualDiskEnabled,
            nfcEnabled: false,
            includeQR: false
        )
        showStory(title: "", body: body, onConfirm: .batchSignImport)
    }

    func handleBatchSignImportKey(_ value: String) -> Bool {
        guard story.onConfirm == .batchSignImport else { return false }
        let key = value.lowercased()
        if key == "1" || key == "b" {
            beginBatchFromVolume(.microSD)
            return true
        }
        if key == "2", virtualDiskEnabled {
            beginBatchFromVolume(.virtDisk)
            return true
        }
        return false
    }

    func beginBatchFromVolume(_ volume: SimulatorCardStandin.Volume) {
        let files = SimulatorCardStandin.psbtFiles(on: volume)
        guard !files.isEmpty else {
            showStory(title: "", body: DoneSigning.noPSBTsFound)
            return
        }
        var queue: [BatchPSBTItem] = []
        for file in files {
            guard let data = try? Data(contentsOf: file.url), !data.isEmpty else { continue }
            queue.append(BatchPSBTItem(name: file.filename, data: data, url: file.url))
        }
        guard !queue.isEmpty else {
            showStory(title: "", body: DoneSigning.noPSBTsFound)
            return
        }
        batchQueue = queue
        startNextBatchPSBT()
    }

    func noteSignedTeleportResult(success: Bool, remaining: Int) {
        guard teleportFromSignedPSBT else { return }
        teleportFromSignedPSBT = false
        if success {
            psbtSignedTitle = DoneSigning.sentByTeleportTitle
            if remaining > 0 {
                psbtSignedPriorMessage = DoneSigning.remainingSignaturesNeeded(remaining)
            }
        } else {
            psbtSignedTitle = DoneSigning.failedToTeleportTitle
        }
        if screen != .psbtSigned { navigate(to: .psbtSigned) }
    }

    var psbtFileBasename: String? {
        let name = psbtSourceName
        let lower = name.lowercased()
        if ["qr", "nfc", "bbqr", "file", "key teleport"].contains(lower) { return nil }
        if name.localizedCaseInsensitiveContains("demo") { return nil }
        return name
    }

    private func presentSignedWriteProblem(_ problem: String, isMissingCard: Bool, volume: SimulatorCardStandin.Volume) {
        if volume == .virtDisk {
            showStory(title: "Error", body: problem)
            return
        }
        let body = problem + "Please insert a card to receive signed transaction, and press OK."
        showStory(title: isMissingCard ? "Need Card" : "Need Card", body: body)
    }

    private func writeSignedNFC(_ message: SimulatorNDEFMessage, noun: String) {
        if SimulatorNFC.isAvailable {
            SimulatorNFC.write(message, prompt: FirmwareCopy.nfcTapPrompt) { [weak self] result in
                guard let self else { return }
                if case .failure(let error) = result {
                    if let nfc = error as? SimulatorNFCError, case .cancelled = nfc { return }
                    self.showStory(title: "", body: error.localizedDescription)
                    return
                }
                self.psbtSignedPriorMessage = DoneSigning.sharedVia(noun, channel: "NFC")
                self.psbtSignedTitle = DoneSigning.signedTitle
            }
            return
        }
        let data: Data
        if let binary = message.records.reversed().compactMap({ record -> Data? in
            if case .binary(_, let payload) = record { return payload }
            return nil
        }).first {
            data = binary
        } else {
            data = signedPSBTData ?? finalizedTransaction?.serialize() ?? Data()
        }
        prepareExport(data: data, filename: "signed-nfc.bin", type: .data)
        psbtSignedPriorMessage = DoneSigning.sharedVia(noun, channel: "NFC")
    }

    func channelForPSBTSource(_ source: String, volume: SimulatorCardStandin.Volume? = nil) -> PSBTInputChannel {
        switch source.lowercased() {
        case "qr", "bbqr": return .qr
        case "nfc": return .nfc
        case "key teleport": return .kt
        default:
            if source.localizedCaseInsensitiveContains("demo") { return .other }
            if volume == .virtDisk { return .vdisk }
            if source.lowercased().hasSuffix(".psbt") { return .sd }
            return .other
        }
    }
}
