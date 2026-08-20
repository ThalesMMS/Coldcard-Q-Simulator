import Foundation

public enum PaperWalletError: Error, Equatable, Sendable {
    case invalidPrivateKey
    case qrFailed
    case templateTooSmall
    case notATemplate
}

public struct PaperWalletFile: Equatable, Sendable {
    public let filename: String
    public let data: Data
}

public struct PaperWalletBundle: Equatable, Sendable {
    public let address: String
    public let wif: String
    public let privateKeyHex: String
    public let isSegwit: Bool
    public let network: BitcoinNetwork
    public let text: PaperWalletFile
    public let pdf: PaperWalletFile?
    public let signature: PaperWalletFile
}

public enum PaperWallet {
    /// Firmware `FEATURE_RELEASE_TIME` (`paper.py`) for `importmulti`.
    public static let featureReleaseTime = 1_574_277_000
    public static let minimumTemplateSize = 20_000

    /// `ADDRESS_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX` (37).
    public static let addressPlaceholder = Data("ADDRESS_XXXXXXXXXXXXXXXXXXXXXXXXXXXXX".utf8)
    /// `PRIVKEY_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX` (51).
    public static let privkeyPlaceholder = Data("PRIVKEY_XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX".utf8)

    /// `%PDF-1.3\n%` + Shift-JIS 千葉県 + ` Coldcard Paper Wallet Template\n`
    public static let templateHeader: Data = {
        var header = Data("%PDF-1.3\n%".utf8)
        header.append(contentsOf: [0x90, 0xE7, 0x97, 0x74, 0x8C, 0xA7])
        header.append(contentsOf: " Coldcard Paper Wallet Template\n".utf8)
        return header
    }()

    public static func isTemplate(_ data: Data) -> Bool {
        data.count >= minimumTemplateSize && data.starts(with: templateHeader)
    }

    public static func privateKey(fromDiceRolls rolls: String) -> Data {
        SHA2.sha256(Data(rolls.utf8))
    }

    public static func diceRollsAreBiased(_ rolls: String) -> Bool {
        SeedCreation.diceRollsAreBiased(rolls)
    }

    public static func generate(privateKey: Data, network: BitcoinNetwork, isSegwit: Bool,
                                template: Data? = nil) throws -> PaperWalletBundle {
        guard Secp256k1.privateKeyIsValid(privateKey) else { throw PaperWalletError.invalidPrivateKey }
        let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey, compressed: true)
        let type: AddressType = isSegwit ? .nativeSegwit : .legacy
        let address = try BitcoinAddress.address(publicKey: publicKey, type: type, network: network)
        var wifPayload = privateKey
        wifPayload.append(0x01)
        let wif = Base58.checkEncode(version: Data([network.wifPrefix]), payload: wifPayload)

        let qrAddr: QRModuleGrid
        let qrWIF: QRModuleGrid
        do {
            if isSegwit {
                qrAddr = try QRCode.version4(address.uppercased(), mode: .alphanumeric)
            } else {
                qrAddr = try QRCode.version4(address, mode: .byte)
            }
            qrWIF = try QRCode.version4(wif, mode: .byte)
        } catch {
            throw PaperWalletError.qrFailed
        }

        let textBody = makeText(address: address, wif: wif, privateKey: privateKey,
                                isSegwit: isSegwit, qrAddr: qrAddr, qrWIF: qrWIF)
        let textName = template == nil ? "\(address).txt" : "\(address)-note.txt"
        let textData = Data(textBody.utf8)
        var files = [PaperWalletFile(filename: textName, data: textData)]
        var hashes: [(Data, String)] = [(SHA2.sha256(textData), textName)]

        var pdfFile: PaperWalletFile?
        if let template {
            guard isTemplate(template) else { throw PaperWalletError.notATemplate }
            let pdfData = try fillPDF(template: template, address: address, wif: wif,
                                      qrAddr: qrAddr, qrWIF: qrWIF)
            let pdfName = "\(address).pdf"
            pdfFile = PaperWalletFile(filename: pdfName, data: pdfData)
            files.append(pdfFile!)
            hashes.append((SHA2.sha256(pdfData), pdfName))
        }

        let sigName = "\(address).sig"
        let sigData = try signFiles(hashes, privateKey: privateKey, type: type, network: network)
        let signature = PaperWalletFile(filename: sigName, data: sigData)
        return PaperWalletBundle(address: address, wif: wif, privateKeyHex: privateKey.hexString,
                                 isSegwit: isSegwit, network: network,
                                 text: files[0], pdf: pdfFile, signature: signature)
    }

    public static func makeText(address: String, wif: String, privateKey: Data, isSegwit: Bool,
                                qrAddr: QRModuleGrid, qrWIF: QRModuleGrid) -> String {
        let descriptor = DescriptorChecksum.append(to: isSegwit ? "wpkh(\(wif))" : "pkh(\(wif))")
        let multi = "{\"timestamp\": \(featureReleaseTime), \"desc\": \"\(descriptor)\"}"
        var body = "Coldcard Generated Paper Wallet\n\n"
        body += "Deposit address:\n\n  \(address)\n\n"
        body += "Private key (WIF=Wallet Import Format):\n\n  \(wif)\n\n"
        body += "Private key (Hex, 32 bytes):\n\n  \(privateKey.hexString)\n\n"
        body += "Bitcoin Core command:\n\n"
        body += "  bitcoin-cli importmulti '[\(multi)]'\n\n"
        body += "# OR (more compatible, but slower)\n\n  bitcoin-cli importprivkey \"\(wif)\"\n\n"
        body += "\n\n--- QR Codes ---   (requires UTF-8, unicode, white background)\n\n\n\n"
        body += "Deposit address:\n\n"
        body += qrAddr.paperWalletASCII()
        body += "\n\n        \(address)\n\n\n\n"
        body += "Private key:\n\n"
        body += qrWIF.paperWalletASCII()
        body += "\n\n        \(wif)\n\n\n\n"
        body += "\n\n\n"
        return body
    }

    public static func fillPDF(template: Data, address: String, wif: String,
                               qrAddr: QRModuleGrid, qrWIF: QRModuleGrid) throws -> Data {
        let addrBytes = Data(address.utf8)
        let wifBytes = Data(wif.utf8)
        let qrAddrHex = qrAddr.paperWalletPDFHex()
        let qrWIFHex = qrWIF.paperWalletPDFHex()
        var output = Data()
        var qrArmed = false
        var qrSkip = false
        var offset = 0
        let newline = UInt8(0x0A)
        while offset < template.count {
            let next = template[offset...].firstIndex(of: newline).map { $0 + 1 } ?? template.count
            let line = template[offset..<next]
            offset = next
            if qrSkip {
                if line.elementsEqual(Data("endstream\n".utf8)) {
                    qrSkip = false
                    output.append(contentsOf: line)
                }
                continue
            }
            var outLine = Data(line)
            if outLine.contains(where: { _ in true }),
               Data(outLine).range(of: Data("Coldcard Paper Wallet Template".utf8)) != nil {
                if let range = outLine.range(of: Data(" Template".utf8)) {
                    outLine.removeSubrange(range)
                }
            } else if outLine.elementsEqual(Data("stream\n".utf8)) {
                qrArmed = true
            } else if qrArmed {
                if outLine.count >= 6, outLine.starts(with: Data("51523A".utf8)) {
                    let isAddr = outLine.starts(with: Data("51523A61646472".utf8))
                    output.append(isAddr ? qrAddrHex : qrWIFHex)
                    qrSkip = true
                    qrArmed = false
                    continue
                } else {
                    qrArmed = false
                }
            }
            if outLine.range(of: Data("XXXXXXXXXX".utf8)) != nil {
                if let range = outLine.range(of: addressPlaceholder) {
                    outLine.replaceSubrange(range, with: addrBytes)
                }
                if let range = outLine.range(of: privkeyPlaceholder) {
                    outLine.replaceSubrange(range, with: wifBytes)
                }
            }
            output.append(outLine)
        }
        return output
    }

    private static func signFiles(_ hashes: [(Data, String)], privateKey: Data,
                                  type: AddressType, network: BitcoinNetwork) throws -> Data {
        let publicKey = try Secp256k1.publicKey(fromPrivateKey: privateKey, compressed: true)
        let message = BitcoinMessageSigner.fileHashMessage(hashesAndNames: hashes)
        let signed = try BitcoinMessageSigner.sign(message, privateKey: privateKey, publicKey: publicKey,
                                                   type: type, network: network, path: "m",
                                                   validateText: false)
        return Data(signed.armored.utf8)
    }
}
