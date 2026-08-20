import Foundation
import ColdcardCore

extension SimulatorStore {
    func startPaperWallets() {
        paperWalletIsSegwit = false
        paperWalletTemplate = nil
        paperWalletTemplateFiles = []
        pendingPaperWalletBundle = nil
        lastPaperWalletQR = nil
        diceForPaperWallet = false
        showStory(title: "", body: FirmwareCopy.paperWalletIntro, onConfirm: .openPaperWallets)
    }

    func pickPaperWalletPDF() {
        let files = SimulatorCardStandin.listFilesForPicker(
            vdiskEnabled: virtualDiskEnabled,
            minSize: PaperWallet.minimumTemplateSize
        ).filter { file in
            file.filename.lowercased().hasSuffix(".pdf")
        }
        var templates: [ListedDiskFile] = []
        for file in files {
            guard let data = try? Data(contentsOf: file.url), PaperWallet.isTemplate(data) else { continue }
            templates.append(file)
        }
        if templates.isEmpty {
            paperWalletTemplate = nil
            showStory(title: "", body: FirmwareCopy.paperWalletNoTemplates)
            return
        }
        paperWalletTemplateFiles = templates
        openMenu(.paperWalletTemplates)
    }

    func setPaperWalletSegwit(_ isSegwit: Bool) {
        paperWalletIsSegwit = isSegwit
        if screen == .menu, currentMenu == .paperWallets {
            selectedMenuIndex = 1
            jumpMenu(to: 1)
        }
    }

    func startPaperWalletDice() {
        diceForPaperWallet = true
        diceMixesWithTRNG = false
        diceWordCount = 24
        diceRolls = ""
        navigate(to: .diceRoll)
    }

    func selectPaperWalletTemplate(_ id: String) {
        guard let file = paperWalletTemplateFiles.first(where: { $0.id == id }),
              let data = try? Data(contentsOf: file.url),
              PaperWallet.isTemplate(data) else {
            paperWalletTemplate = nil
            showStory(title: "", body: FirmwareCopy.paperWalletNoTemplates)
            return
        }
        paperWalletTemplate = (file.filename, data)
        paperWalletTemplateFiles = []
        if history.last == .menu { _ = history.popLast() }
        if menuStack.last == .paperWallets { _ = menuStack.popLast() }
        currentMenu = .paperWallets
        screen = .menu
        selectedMenuIndex = 0
        jumpMenu(to: 0)
    }

    func generatePaperWallet(haveKey: Data? = nil) {
        let network = self.network
        let isSegwit = paperWalletIsSegwit
        let template = paperWalletTemplate?.data
        Task { @MainActor in
            var key = haveKey
            if key == nil {
                await dramaticPause(BusyPhase.pickingKey.rawValue, seconds: 2)
                do {
                    var generated = try SecureRandom.bytes(count: 32)
                    var spins = 0
                    while !Secp256k1.privateKeyIsValid(generated), spins < 8 {
                        generated = try SecureRandom.bytes(count: 32)
                        spins += 1
                    }
                    guard Secp256k1.privateKeyIsValid(generated) else { return }
                    key = generated
                } catch {
                    showStory(title: "", body: "Failed to write!\n\n\(error.localizedDescription)")
                    return
                }
            }
            guard let privateKey = key else { return }
            beginWorking(.rendering)
            let result = await Task.detached(priority: .userInitiated) { () -> Result<PaperWalletBundle, Error> in
                Result {
                    try PaperWallet.generate(privateKey: privateKey, network: network,
                                             isSegwit: isSegwit, template: template)
                }
            }.value
            endWorking()
            switch result {
            case .success(let bundle):
                pendingPaperWalletBundle = bundle
                lastPaperWalletQR = (bundle.address, bundle.wif, bundle.isSegwit)
                if virtualDiskEnabled {
                    showStory(title: "", body: FirmwareCopy.paperWalletSavePrompt, onConfirm: .paperWalletSave)
                } else {
                    savePendingPaperWallet(to: .microSD)
                }
            case .failure(let error):
                pendingPaperWalletBundle = nil
                showStory(title: "", body: "Failed to write!\n\n\(error.localizedDescription)")
            }
        }
    }

    func savePendingPaperWallet(to volume: SimulatorCardStandin.Volume) {
        guard let bundle = pendingPaperWalletBundle else {
            returnToPaperWalletsMenu(selecting: 3)
            return
        }
        beginWorking(.saving)
        do {
            _ = try writeCardStandin(bundle.text.data, named: bundle.text.filename, to: volume)
            var created = [bundle.text.filename]
            if let pdf = bundle.pdf {
                _ = try writeCardStandin(pdf.data, named: pdf.filename, to: volume)
                created.append(pdf.filename)
            }
            _ = try writeCardStandin(bundle.signature.data, named: bundle.signature.filename, to: volume)
            created.append(bundle.signature.filename)
            pendingPaperWalletBundle = nil
            endWorking()
            var body = "Done! Created file(s):\n\n\(created[0])"
            for name in created.dropFirst() {
                body += "\n\n\(name)"
            }
            story = StoryPresentation(title: "", body: body, onConfirm: .paperWalletDone, hintQR: true)
            screen = .story
            selectedMenuIndex = 0
            storyTop = 0
        } catch {
            pendingPaperWalletBundle = nil
            endWorking()
            showStory(title: "", body: "Failed to write!\n\n\(error.localizedDescription)")
        }
    }

    func presentPaperWalletQR() {
        guard let paper = lastPaperWalletQR else { return }
        let address = paper.isSegwit ? paper.address.uppercased() : paper.address
        qrPresentation = QRPresentation(title: "Paper Wallet", payloads: [address, paper.wif], sensitive: true)
    }

    func finishPaperWalletDice() {
        if diceRolls.count < 99 {
            showStory(title: "", body: FirmwareCopy.paperWalletDiceNotEnough(count: diceRolls.count),
                      onConfirm: .continueDiceRolling)
            return
        }
        if PaperWallet.diceRollsAreBiased(diceRolls) {
            showStory(title: "", body: FirmwareCopy.badDice, onConfirm: .abortDice)
            return
        }
        let key = PaperWallet.privateKey(fromDiceRolls: diceRolls)
        diceRolls = ""
        diceForPaperWallet = false
        guard Secp256k1.privateKeyIsValid(key) else {
            returnToPaperWalletsMenu(selecting: 2)
            return
        }
        generatePaperWallet(haveKey: key)
    }

    func returnToPaperWalletsMenu(selecting index: Int = 0) {
        diceForPaperWallet = false
        diceRolls = ""
        pendingPaperWalletBundle = nil
        history.removeAll { $0 == .diceRoll || $0 == .story }
        currentMenu = .paperWallets
        screen = .menu
        selectedMenuIndex = index
        jumpMenu(to: index)
        errorMessage = nil
        statusMessage = nil
    }

    func openPaperWalletsMenuFromIntro() {
        menuStack.append(currentMenu)
        currentMenu = .paperWallets
        screen = .menu
        selectedMenuIndex = 0
        jumpMenu(to: 0)
        errorMessage = nil
        statusMessage = nil
    }

    func cancelPaperWalletIntro() {
        if history.last == .menu {
            _ = history.popLast()
            screen = .menu
            selectedMenuIndex = 0
        }
    }

    func handlePaperWalletQRKey() -> Bool {
        guard screen == .story, story.onConfirm == .paperWalletDone, lastPaperWalletQR != nil else { return false }
        presentPaperWalletQR()
        return true
    }

    func handlePaperWalletStoryKey(_ value: String) -> Bool {
        guard story.onConfirm == .paperWalletSave else { return false }
        if value == "1" {
            story.onConfirm = nil
            savePendingPaperWallet(to: .microSD)
            return true
        }
        if value == "2", virtualDiskEnabled {
            story.onConfirm = nil
            savePendingPaperWallet(to: .virtDisk)
            return true
        }
        return true
    }

    func confirmPaperWalletStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .openPaperWallets:
            openPaperWalletsMenuFromIntro()
            return true
        case .paperWalletSave:
            pendingPaperWalletBundle = nil
            returnToPaperWalletsMenu(selecting: 3)
            return true
        case .paperWalletDone:
            returnToPaperWalletsMenu(selecting: 3)
            return true
        case .abortDice where diceForPaperWallet:
            returnToPaperWalletsMenu(selecting: 2)
            return true
        default:
            return false
        }
    }

    func performPaperWalletCommand(_ command: SimulatorCommand) -> Bool {
        switch command {
        case .startPaperWallets:
            startPaperWallets()
        case .pickPaperWalletPDF:
            pickPaperWalletPDF()
        case .setPaperWalletSegwit(let segwit):
            setPaperWalletSegwit(segwit)
        case .paperWalletUseDice:
            startPaperWalletDice()
        case .generatePaperWallet:
            generatePaperWallet(haveKey: nil)
        case .selectPaperWalletTemplate(let id):
            selectPaperWalletTemplate(id)
        default:
            return false
        }
        return true
    }

    func handlePaperWalletBack() -> Bool {
        if screen == .story, story.onConfirm == .abortDice, diceForPaperWallet {
            story.onConfirm = nil
            returnToPaperWalletsMenu(selecting: 2)
            return true
        }
        if screen == .story, story.onConfirm == .openPaperWallets {
            story.onConfirm = nil
            cancelPaperWalletIntro()
            return true
        }
        if screen == .story, story.onConfirm == .paperWalletSave || story.onConfirm == .paperWalletDone {
            pendingPaperWalletBundle = nil
            story.onConfirm = nil
            returnToPaperWalletsMenu(selecting: 3)
            return true
        }
        if screen == .story, story.onConfirm == .continueDiceRolling, diceForPaperWallet {
            story.onConfirm = nil
            returnToPaperWalletsMenu(selecting: 2)
            return true
        }
        if screen == .menu, currentMenu == .paperWalletTemplates {
            paperWalletTemplate = nil
            paperWalletTemplateFiles = []
        }
        return false
    }
}
