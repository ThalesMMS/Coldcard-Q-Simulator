import Foundation
import UIKit
import ColdcardCore

/// App-layer HTTP(S) GET to the user `ptxurl`. `ColdcardCore` stays network-free.
enum PushTxTransport {
    struct Response: Sendable {
        var status: Int
        var submittedQuery: Bool
        var openedBrowser: Bool
        var summary: String
    }

    static func get(_ urlString: String) async throws -> Response {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw SimulatorNFCError.failed("Push Tx URL is not http:// or https://.")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("ColdcardQSimulator/1.0", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let usesFragment = urlString.contains("#")
        return Response(
            status: status,
            submittedQuery: !usesFragment,
            openedBrowser: false,
            summary: status == 0 ? "No HTTP status." : "HTTP \(status)"
        )
    }
}

extension SimulatorStore {
    var hasPushtxURL: Bool {
        let value = preferences.ptxurl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !value.isEmpty
    }

    func beginNFCPushTxSetup() {
        let current = preferences.ptxurl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ToggleMenuStory.showsPushTxIntro(urlMissing: current.isEmpty) {
            showStory(title: "PUSH TX", body: FirmwareCopy.pushTxIntro, onConfirm: .continuePushtxSetup)
            return
        }
        openPushTxChooserRequiringNFC()
    }

    func continuePushtxSetupAfterIntro() {
        back()
        openPushTxChooserRequiringNFC()
    }

    func openPushTxChooserRequiringNFC() {
        if preferences.nfcSharingEnabled {
            openMenu(.nfcPushTx)
            return
        }
        showStory(title: "", body: FirmwareCopy.nfcRequiredToEnable, onConfirm: .enableNFCForFeature)
    }

    func enableNFCForPushTxFeature() {
        preferences.nfcSharingEnabled = true
        persistPreferencesQuietly()
        back()
        openMenu(.nfcPushTx)
    }

    func applyPushtxURL(_ url: String?) {
        let trimmed = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            preferences.ptxurl = nil
        } else {
            preferences.ptxurl = trimmed
        }
        persistPreferencesQuietly()
        back()
    }

    func beginEditPushtxURL() {
        let current = preferences.ptxurl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isStock = PushTx.suppliers.contains(where: { $0.url == current })
        textEntryIsPushtxURL = true
        passphraseInput = (!current.isEmpty && !isStock) ? current : "http"
        navigate(to: .passphrase)
    }

    func commitPushtxURLFromField() {
        let nv = passphraseInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if nv.isEmpty {
            textEntryIsPushtxURL = false
            passphraseInput = ""
            preferences.ptxurl = nil
            persistPreferencesQuietly()
            back()
            return
        }
        if let problem = PushTx.validateCustomURL(nv) {
            showStory(title: "", body: problem + " Try again.", onConfirm: .retryPushtxURLEdit)
            return
        }
        textEntryIsPushtxURL = false
        passphraseInput = ""
        preferences.ptxurl = nv
        persistPreferencesQuietly()
        back()
        openMenu(.nfcPushTx, remember: false)
    }

    func retryPushtxURLEdit() {
        back()
        textEntryIsPushtxURL = true
        if screen != .passphrase {
            navigate(to: .passphrase)
        }
    }

    func beginPushTransaction() {
        guard hasPushtxURL else { return }
        pickingPushTxn = true
        let files = SimulatorCardStandin.listFilesForPicker(
            vdiskEnabled: virtualDiskEnabled,
            minSize: 10,
            maxSize: PushTx.maxNFCSize * 2
        ).filter { $0.filename.lowercased().hasSuffix(".txn") }
        listedDiskFiles = files
        if files.isEmpty {
            showStory(title: "", body: FirmwareCopy.nfcTxnMissing, onConfirm: .pickPushTxnFromFiles)
            return
        }
        openMenu(.listedFiles)
    }

    func pushTransaction(fromFile file: ListedDiskFile) {
        let data = (try? Data(contentsOf: file.url)) ?? Data()
        pushTransaction(data: data, filename: file.filename)
    }

    func pushTransaction(data: Data, filename: String) {
        guard let prefix = preferences.ptxurl, !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showStory(title: "ERROR", body: FirmwareCopy.nfcTxnMissing)
            return
        }
        let txn: Data
        do {
            txn = try PushTx.decodeTxnFile(data)
        } catch {
            showStory(title: "ERROR", body: "Doesn't look like txn?")
            return
        }
        let url: String
        do {
            url = try PushTx.txnToPushTxURL(prefix: prefix, transaction: txn, network: network)
        } catch PushTxError.tooBig {
            showStory(title: "ERROR", body: FirmwareCopy.pushTxTooBig)
            return
        } catch {
            showStory(title: "ERROR", body: error.localizedDescription)
            return
        }
        let txid = PushTx.txidFromFilename(filename)
        let line2: String
        if let txid {
            line2 = "Signed TXID: \(txid.prefix(8))⋯\(txid.suffix(8))"
        } else {
            var label = "File: " + filename
            if label.count > 34 { label = String(label.prefix(32)) + "⋯" }
            line2 = label
        }
        performPushTxRequest(url: url, line2: line2, afterSign: false)
    }

    func tryPushTxAfterSign() {
        guard hasPushtxURL, preferences.nfcSharingEnabled, postSignIsComplete, let transaction = finalizedTransaction else {
            presentDoneSigning()
            return
        }
        let raw = transaction.serialize()
        let prefix = preferences.ptxurl ?? ""
        let url: String
        do {
            url = try PushTx.txnToPushTxURL(prefix: prefix, transaction: raw, network: network)
        } catch {
            presentDoneSigning()
            return
        }
        beginWorking(.wait)
        Task { @MainActor in
            do {
                _ = try await PushTxTransport.get(url)
                endWorking()
                writePushTxURLToTagIfPossible(url)
                presentDoneSigning(title: DoneSigning.pushedTitle, firstPass: false)
            } catch {
                endWorking()
                presentDoneSigning()
            }
        }
    }

    private func performPushTxRequest(url: String, line2: String, afterSign: Bool) {
        beginWorking(.wait)
        Task { @MainActor in
            var body = line2 + "\n\n" + FirmwareCopy.pushTxHTTPHint
            if network == .mainnet {
                body += "\n\n" + FirmwareCopy.mainnetNotHardwareWallet
            }
            do {
                let response = try await PushTxTransport.get(url)
                body += "\n\n" + response.summary
                if url.contains("#"), let parsed = URL(string: url) {
                    _ = await UIApplication.shared.open(parsed)
                    body += "\nOpened the fragment URL in the browser (firmware phone-browser analog)."
                } else if response.submittedQuery {
                    body += "\nQuery string was sent with GET (URL ends in ? or &)."
                }
            } catch {
                endWorking()
                if afterSign { return }
                showStory(title: "ERROR", body: error.localizedDescription)
                return
            }
            endWorking()
            writePushTxURLToTagIfPossible(url)
            let title = afterSign ? "TX Pushed" : "PUSH TX"
            showStory(title: title, body: body, onConfirm: pickingPushTxn ? .continuePushTxnPicker : nil)
        }
    }

    private func writePushTxURLToTagIfPossible(_ urlString: String) {
        guard SimulatorNFC.isAvailable, let url = URL(string: urlString) else { return }
        SimulatorNFC.write(.uri(url), prompt: "Tap to broadcast, CANCEL when done") { _ in }
    }

    func continuePushTxnPicker() {
        if screen == .story { back() }
        pickingPushTxn = true
        let files = SimulatorCardStandin.listFilesForPicker(
            vdiskEnabled: virtualDiskEnabled,
            minSize: 10,
            maxSize: PushTx.maxNFCSize * 2
        ).filter { $0.filename.lowercased().hasSuffix(".txn") }
        listedDiskFiles = files
        if files.isEmpty {
            showStory(title: "", body: FirmwareCopy.nfcTxnMissing, onConfirm: .pickPushTxnFromFiles)
            return
        }
        if screen != .menu || currentMenu != .listedFiles {
            openMenu(.listedFiles)
        }
    }
}
