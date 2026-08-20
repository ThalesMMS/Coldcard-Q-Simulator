import Foundation
import Testing
@testable import ColdcardCore

@Test func readyToSignQImportPromptMatchesFirmwareSlotBOnly() {
    let off = FirmwareImportPrompt.qImportPrompt(
        title: "PSBT", slotBOnly: true, virtualDiskEnabled: false, nfcEnabled: false
    )
    #expect(off == "Press (B) to import PSBT from lower slot SD Card, QR to scan QR code.")

    let vd = FirmwareImportPrompt.qImportPrompt(
        title: "PSBT", slotBOnly: true, virtualDiskEnabled: true, nfcEnabled: false
    )
    #expect(vd == "Press (B) to import PSBT from lower slot SD Card, press (2) to import from Virtual Disk, QR to scan QR code.")

    let nfc = FirmwareImportPrompt.qImportPrompt(
        title: "PSBT", slotBOnly: true, virtualDiskEnabled: false, nfcEnabled: true
    )
    #expect(nfc == "Press (B) to import PSBT from lower slot SD Card, press NFC to import via NFC, QR to scan QR code.")

    let both = FirmwareImportPrompt.qImportPrompt(
        title: "PSBT", slotBOnly: true, virtualDiskEnabled: true, nfcEnabled: true
    )
    #expect(both == "Press (B) to import PSBT from lower slot SD Card, press (2) to import from Virtual Disk, press NFC to import via NFC, QR to scan QR code.")

    #expect(!both.contains("Press (1)"))
    #expect(both.contains("(B)"))
    #expect(both.contains("press (2) to import from Virtual Disk"))
    #expect(both.contains("press NFC to import via NFC"))
    #expect(both.hasSuffix(", QR to scan QR code."))
}

@Test func importXPRVPromptMatchesFirmwareImportExportPrompt() {
    let off = FirmwareImportPrompt.qImportPrompt(
        title: FirmwareImportPrompt.extendedPrivateKeyFileTitle,
        slotBOnly: false,
        virtualDiskEnabled: false,
        nfcEnabled: false
    )
    #expect(off.hasPrefix("Press (1) to import extended private key file from SD Card"))
    #expect(off.contains("(B) for lower slot"))
    #expect(off.hasSuffix(", QR to scan QR code."))
    #expect(!off.contains("NFC"))
    #expect(!off.contains("Virtual Disk"))

    let both = FirmwareImportPrompt.qImportPrompt(
        title: FirmwareImportPrompt.extendedPrivateKeyFileTitle,
        slotBOnly: false,
        virtualDiskEnabled: true,
        nfcEnabled: true
    )
    #expect(both.contains("press (2) to import from Virtual Disk"))
    #expect(both.contains("press NFC to import via NFC"))
    #expect(both.contains("QR to scan QR code"))
    #expect(FirmwareImportPrompt.importedXPRVOrigin == "Imported XPRV")
    #expect(FirmwareImportPrompt.importedXPRVOrigin != "Import XPRV")
}

@Test func importXPRVParsesFileLineAndNFCPayload() {
    let file = "ignore this\ntprv8ZgxMBicQKsPe\nmore"
    #expect(FirmwareImportPrompt.firstPrivateKeyLine(in: file)?.contains("tprv") == true)
    #expect(FirmwareImportPrompt.parseExtendedPrivateKeyToken("prefix tprv8ZgxMBicQKsPe trailing") == "tprv8ZgxMBicQKsPe")
    #expect(FirmwareImportPrompt.parseExtendedPrivateKeyToken("no secret here") == nil)

    let hit = FirmwareImportPrompt.extendedPrivateKey(fromNFCPayloads: [Data("hello".utf8), Data("  tprvSECRET  ".utf8)])
    #expect(hit == "tprvSECRET")
    #expect(FirmwareImportPrompt.extendedPrivateKey(fromNFCPayloads: [Data("hello".utf8)]) == nil)
    #expect(FirmwareImportPrompt.xprvNFCMissing == "Unable to find extended private key.")
    #expect(FirmwareImportPrompt.scanXPRVPrompt == "Scan XPRV from a QR code")
}
