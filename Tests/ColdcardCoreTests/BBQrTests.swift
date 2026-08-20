import XCTest
@testable import ColdcardCore

final class BBQrTests: XCTestCase {
    func testBase32Vectors() throws {
        XCTAssertEqual(Base32.encode(Data()), "")
        XCTAssertEqual(Base32.encode(Data("f".utf8)), "MY")
        XCTAssertEqual(Base32.encode(Data("foobar".utf8)), "MZXW6YTBOI")
        XCTAssertEqual(try Base32.decode("MZXW6YTBOI======"), Data("foobar".utf8))
    }

    func testBBQrRoundTripShuffledWithDuplicate() throws {
        let data = Data((0..<9_000).map { UInt8($0 & 0xff) })
        let parts = try BBQr.encode(data, fileType: .psbt, maximumCharactersPerQR: 700)
        XCTAssertGreaterThan(parts.count, 1)
        var collector = BBQrCollector()
        var completed: BBQrDecodedPayload?
        let scans = Array(parts.reversed()) + [parts[0]]
        for part in scans {
            if case .complete(let payload) = try collector.add(part) { completed = payload }
        }
        XCTAssertEqual(completed?.fileType, BBQrFileType.psbt.rawValue)
        XCTAssertEqual(completed?.data, data)
    }

    func testZlibRoundTrip() throws {
        let data = Data((0..<2_000).map { UInt8($0 & 0xff) })
        let parts = try BBQr.encode(data, fileType: .psbt, encoding: .zlib, maximumCharactersPerQR: 700)
        XCTAssertTrue(parts.allSatisfy { $0.hasPrefix("B$Z") })
        let decoded = try BBQr.decode(parts)
        XCTAssertEqual(decoded.data, data)
    }

    func testColdcardHeaderFormat() throws {
        let parts = try BBQr.encode(Data("hello".utf8), fileType: .unicode, maximumCharactersPerQR: 120)
        XCTAssertEqual(parts, ["B$2U0100NBSWY3DP"])
        let decoded = try BBQr.decode(parts)
        XCTAssertEqual(decoded.fileType, Character("U"))
        XCTAssertEqual(decoded.data, Data("hello".utf8))
    }

    func testEmptyPartIsInvalid() {
        XCTAssertThrowsError(try BBQr.decode(["B$2U0100"])) { error in
            XCTAssertEqual(error as? BBQrError, .invalidPart)
        }
    }

    func testTYPELabelsMatchFirmwareFileLabel() {
        XCTAssertEqual(BBQrFileType.psbt.label, "PSBT File")
        XCTAssertEqual(BBQrFileType.transaction.label, "Transaction")
        XCTAssertEqual(BBQrFileType.json.label, "JSON")
        XCTAssertEqual(BBQrFileType.cbor.label, "CBOR")
        XCTAssertEqual(BBQrFileType.unicode.label, "Unicode Text")
        XCTAssertEqual(BBQrFileType.executable.label, "Executable")
        XCTAssertEqual(BBQrFileType.binary.label, "Binary")
        XCTAssertEqual(BBQrFileType.keyTeleportReceive.label, "KT Rx")
        XCTAssertEqual(BBQrFileType.keyTeleportTransmit.label, "KT Tx")
        XCTAssertEqual(BBQrFileType.keyTeleportPSBT.label, "KT PSBT")
        XCTAssertEqual(BBQrFileType.label(for: "P"), "PSBT File")
        XCTAssertEqual(BBQrFileType.label(for: "?"), "Unknown: ?")
        XCTAssertEqual(BBQr.decompressingTitle, "Decompressing...")
        XCTAssertEqual(ScanAnything.bbqrNotUsefulMessage(fileType: "X"), "Sorry, Executable not useful.")
        XCTAssertEqual(ScanAnything.bbqrNotUsefulMessage(fileType: "B"), "Sorry, Binary not useful.")
        XCTAssertEqual(ScanAnything.bbqrNotUsefulMessage(fileType: "?"), "Sorry, Unknown FileType not useful.")
        XCTAssertEqual(ScanAnything.bbqrExpectedTextMessage(fileType: "P"), "Expected text, got PSBT File")
        XCTAssertEqual(ScanAnything.bbqrExpectedTextMessage(fileType: "?"), "Expected text, got ?")
    }

    func testScanProgressSurfacesTYPELabelsAndRuntHold() throws {
        let runt = hexPart(partCount: 3, index: 2, byteCount: 4, fill: 0xCC)
        var collector = BBQrCollector()
        guard case .progress(let progress) = try collector.add(runt) else {
            return XCTFail("runt-first should stay in progress")
        }
        XCTAssertTrue(progress.awaitingRuntPlacement)
        XCTAssertEqual(progress.fileLabel, "Unicode Text")
        XCTAssertEqual(progress.instructionLine, "Keep scanning more...")
        XCTAssertEqual(progress.countLine, "Unicode Text: 1 of 3 parts")
        XCTAssertEqual(progress.partPattern, "-  -  3")
        XCTAssertFalse(progress.skipsProgressUI)
        XCTAssertEqual(progress.fraction, 1.0 / 3.0)
    }

    func testCollectorRejectsOversizedPartAgainstBlksizeBeforeSeriesCompletes() throws {
        // Firmware sets blksize from the first non-runt packet and rejects the next
        // mismatch immediately (`bbqr.py` save_packet), without waiting for part 3.
        let middle = hexPart(partCount: 3, index: 1, byteCount: 8, fill: 0xAA)
        let first = hexPart(partCount: 3, index: 0, byteCount: 10, fill: 0xBB)
        var collector = BBQrCollector()
        guard case .progress(let afterMiddle) = try collector.add(middle) else {
            return XCTFail("middle-first should be progress")
        }
        XCTAssertFalse(afterMiddle.awaitingRuntPlacement)
        XCTAssertEqual(afterMiddle.collected, 1)

        switch try collector.add(first) {
        case .progress(let progress):
            XCTAssertTrue(progress.corrupt)
            XCTAssertEqual(collector.collectedCount, 0)
        case .complete:
            XCTFail("size mismatch must not complete")
        }
    }

    func testRuntFirstThenBlksizeOffsetsRoundTrip() throws {
        let p0 = hexPart(partCount: 3, index: 0, byteCount: 8, fill: 0x11)
        let p1 = hexPart(partCount: 3, index: 1, byteCount: 8, fill: 0x22)
        let p2 = hexPart(partCount: 3, index: 2, byteCount: 3, fill: 0x33)
        var collector = BBQrCollector()
        XCTAssertEqual(try collector.add(p2).isComplete, false)
        XCTAssertEqual(try collector.add(p0).isComplete, false)
        guard case .complete(let payload) = try collector.add(p1) else {
            return XCTFail("expected complete after placing runt")
        }
        XCTAssertEqual(payload.encoding, .hex)
        XCTAssertEqual(payload.data, Data(repeating: 0x11, count: 8)
            + Data(repeating: 0x22, count: 8)
            + Data(repeating: 0x33, count: 3))
    }

    func testZlibCompleteReportsEncodingForDecompressingScreen() throws {
        let data = Data((0..<400).map { UInt8($0 & 0xff) })
        let parts = try BBQr.encode(data, fileType: .json, encoding: .zlib, maximumCharactersPerQR: 200)
        XCTAssertGreaterThan(parts.count, 1)
        var collector = BBQrCollector()
        var lastProgress: BBQrScanProgress?
        var completed: BBQrDecodedPayload?
        for part in parts {
            switch try collector.add(part) {
            case .progress(let progress):
                lastProgress = progress
                XCTAssertEqual(progress.fileLabel, "JSON")
                XCTAssertTrue(progress.countLine.hasPrefix("JSON:"))
            case .complete(let payload):
                completed = payload
            }
        }
        XCTAssertEqual(completed?.encoding, .zlib)
        XCTAssertEqual(completed?.data, data)
        XCTAssertEqual(lastProgress?.instructionLine, "Keep scanning more...")
    }

    func testPartPatternMatchesFirmwareDrawBBQrProgress() {
        let keep = BBQrScanProgress(
            fileType: "P",
            collected: 1,
            total: 3,
            gotParts: [0],
            currentIndex: 1,
            corrupt: true,
            awaitingRuntPlacement: false
        )
        XCTAssertEqual(keep.partPattern, "1  X  -")
        XCTAssertEqual(keep.instructionLine, "Keep scanning more...")
        XCTAssertEqual(keep.countLine, "PSBT File: 1 of 3 parts")
        XCTAssertEqual(keep.statusMessage, "1  X  -\nKeep scanning more...\nPSBT File: 1 of 3 parts")

        let done = BBQrScanProgress(
            fileType: "P",
            collected: 3,
            total: 3,
            gotParts: [0, 1, 2],
            currentIndex: 2,
            corrupt: false,
            awaitingRuntPlacement: false
        )
        XCTAssertEqual(done.instructionLine, "Got all parts!")
        XCTAssertEqual(done.partPattern, "1  2  3")

        let single = BBQrScanProgress(
            fileType: "P",
            collected: 1,
            total: 1,
            gotParts: [0],
            currentIndex: 0,
            corrupt: false,
            awaitingRuntPlacement: false
        )
        XCTAssertTrue(single.skipsProgressUI)
    }

    private func hexPart(fileType: Character = "U", partCount: Int, index: Int, byteCount: Int, fill: UInt8) -> String {
        let header = try! BBQrHeader(encoding: .hex, fileType: fileType, partCount: partCount, partIndex: index)
        let body = Data(repeating: fill, count: byteCount).hexString.uppercased()
        return header.text + body
    }
}

private extension BBQrCollectionResult {
    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}
