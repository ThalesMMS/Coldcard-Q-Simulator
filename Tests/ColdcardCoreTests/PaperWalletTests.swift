import XCTest
@testable import ColdcardCore

final class PaperWalletTests: XCTestCase {
    func testDiceRollsMatchFirmwareSHA256() {
        let rolls = String(repeating: "123456", count: 17)
        XCTAssertEqual(rolls.count, 102)
        let key = PaperWallet.privateKey(fromDiceRolls: rolls)
        XCTAssertEqual(key.count, 32)
        XCTAssertEqual(key, SHA2.sha256(Data(rolls.utf8)))
        XCTAssertTrue(Secp256k1.privateKeyIsValid(key))
    }

    func testBiasedDiceMatchesFirmwareThreshold() {
        XCTAssertFalse(PaperWallet.diceRollsAreBiased(String(repeating: "123456", count: 17)))
        XCTAssertTrue(PaperWallet.diceRollsAreBiased(String(repeating: "1", count: 99)))
        XCTAssertTrue(PaperWallet.diceRollsAreBiased(String(repeating: "64", count: 50)))
        XCTAssertTrue(PaperWallet.diceRollsAreBiased("1"))
    }

    func testClassicAndSegwitFromKnownKey() throws {
        let privateKey = try Data(hex: "0000000000000000000000000000000000000000000000000000000000000001")
        let classic = try PaperWallet.generate(privateKey: privateKey, network: .testnet, isSegwit: false)
        XCTAssertEqual(classic.wif.first, "c")
        XCTAssertTrue(classic.address.hasPrefix("m") || classic.address.hasPrefix("n"))
        XCTAssertEqual(classic.privateKeyHex, privateKey.hexString)
        XCTAssertTrue(classic.text.filename.hasSuffix(".txt"))
        XCTAssertEqual(classic.text.filename, "\(classic.address).txt")
        XCTAssertEqual(classic.signature.filename, "\(classic.address).sig")
        XCTAssertNil(classic.pdf)

        let text = String(decoding: classic.text.data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("Coldcard Generated Paper Wallet"))
        XCTAssertTrue(text.contains("Deposit address:"))
        XCTAssertTrue(text.contains(classic.address))
        XCTAssertTrue(text.contains("WIF=Wallet Import Format"))
        XCTAssertTrue(text.contains(classic.wif))
        XCTAssertTrue(text.contains(privateKey.hexString))
        XCTAssertTrue(text.contains("importmulti"))
        XCTAssertTrue(text.contains("importprivkey"))
        XCTAssertTrue(text.contains("pkh(\(classic.wif))"))
        XCTAssertTrue(text.contains("\"timestamp\": 1574277000"))
        XCTAssertTrue(text.contains("--- QR Codes ---"))
        XCTAssertTrue(text.contains("\u{2588}"))

        let parsed = try BitcoinMessageSigner.parseArmored(String(decoding: classic.signature.data, as: UTF8.self))
        XCTAssertEqual(parsed.address, classic.address)
        XCTAssertNoThrow(try BitcoinMessageSigner.verify(message: parsed.message, address: parsed.address,
                                                         signatureBase64: parsed.signature))

        let segwit = try PaperWallet.generate(privateKey: privateKey, network: .testnet, isSegwit: true)
        XCTAssertTrue(segwit.address.hasPrefix("tb1q"))
        XCTAssertEqual(segwit.wif, classic.wif)
        let segText = String(decoding: segwit.text.data, as: UTF8.self)
        XCTAssertTrue(segText.contains("wpkh(\(segwit.wif))"))
        XCTAssertEqual(segwit.signature.filename, "\(segwit.address).sig")
        let segParsed = try BitcoinMessageSigner.parseArmored(String(decoding: segwit.signature.data, as: UTF8.self))
        XCTAssertEqual(segParsed.address, segwit.address)
        XCTAssertNoThrow(try BitcoinMessageSigner.verify(message: segParsed.message, address: segParsed.address,
                                                         signatureBase64: segParsed.signature))
    }

    func testMainnetPrefixes() throws {
        let privateKey = try Data(hex: "0000000000000000000000000000000000000000000000000000000000000001")
        let classic = try PaperWallet.generate(privateKey: privateKey, network: .mainnet, isSegwit: false)
        XCTAssertEqual(classic.address.first, "1")
        XCTAssertEqual(classic.wif.first, "K")
        let segwit = try PaperWallet.generate(privateKey: privateKey, network: .mainnet, isSegwit: true)
        XCTAssertTrue(segwit.address.hasPrefix("bc1q"))
    }

    func testQRVersion4SizeAndFinders() throws {
        let grid = try QRCode.version4("HELLO WORLD", mode: .alphanumeric)
        XCTAssertEqual(grid.size, 33)
        XCTAssertTrue(grid.module(x: 0, y: 0))
        XCTAssertTrue(grid.module(x: 32, y: 0))
        XCTAssertTrue(grid.module(x: 0, y: 32))
        XCTAssertTrue(grid.module(x: 8, y: 25))
        let ascii = grid.paperWalletASCII()
        XCTAssertEqual(ascii.split(separator: "\n").count, 33)
        XCTAssertEqual(grid.paperWalletPDFHex().count, 33 * 8 * (33 * 2 + 1))
    }

    func testTemplateHeaderAndPDFFill() throws {
        XCTAssertFalse(PaperWallet.isTemplate(Data("%PDF-1.3\n".utf8)))
        var template = PaperWallet.templateHeader
        XCTAssertFalse(PaperWallet.isTemplate(template))
        template.append(Data(repeating: 0x20, count: PaperWallet.minimumTemplateSize))
        XCTAssertTrue(PaperWallet.isTemplate(template))

        var body = Data()
        body.append(PaperWallet.templateHeader)
        body.append(contentsOf: "stream\n".utf8)
        body.append(contentsOf: "51523A61646472".utf8)
        body.append(contentsOf: [0x0A])
        body.append(contentsOf: "oldqr\nendstream\n".utf8)
        body.append(contentsOf: "stream\n".utf8)
        body.append(contentsOf: "51523A706B".utf8)
        body.append(contentsOf: [0x0A])
        body.append(contentsOf: "oldpk\nendstream\n".utf8)
        body.append(PaperWallet.addressPlaceholder)
        body.append(contentsOf: [0x0A])
        body.append(PaperWallet.privkeyPlaceholder)
        body.append(contentsOf: [0x0A])
        body.append(Data(repeating: 0x20, count: PaperWallet.minimumTemplateSize))

        let privateKey = try Data(hex: "0000000000000000000000000000000000000000000000000000000000000001")
        let bundle = try PaperWallet.generate(privateKey: privateKey, network: .testnet, isSegwit: false,
                                              template: body)
        XCTAssertEqual(bundle.text.filename, "\(bundle.address)-note.txt")
        let pdf = try XCTUnwrap(bundle.pdf)
        XCTAssertEqual(pdf.filename, "\(bundle.address).pdf")
        let pdfString = String(decoding: pdf.data, as: UTF8.self)
        XCTAssertTrue(pdf.data.range(of: Data("Coldcard Paper Wallet Template".utf8)) == nil)
        XCTAssertTrue(pdf.data.range(of: Data("Coldcard Paper Wallet".utf8)) != nil)
        XCTAssertTrue(pdfString.contains(bundle.address))
        XCTAssertTrue(pdfString.contains(bundle.wif))
        XCTAssertTrue(pdf.data.range(of: Data("oldqr".utf8)) == nil)
        XCTAssertTrue(pdf.data.range(of: Data("51523A".utf8)) == nil)
    }

    func testRejectsInvalidKey() {
        XCTAssertThrowsError(try PaperWallet.generate(privateKey: Data(repeating: 0, count: 32),
                                                      network: .testnet, isSegwit: false))
    }
}
