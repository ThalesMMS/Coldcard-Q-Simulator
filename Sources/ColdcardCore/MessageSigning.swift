import Foundation

public enum MessageSigningError: Error, Equatable {
    case unsupportedAddressType
    case missingPrivateKey
    case mustBeAsciiPrintable
    case mustBeAsciiPrintableTabOrNewline
    case tooShort
    case tooLong(Int)
    case tooManySpaces
    case leadingSpace
    case trailingSpace
    /// Firmware `parse_armored_signature_file` FAILURE payload after the prefix.
    case malformedSignatureFile(String)
    case invalidSignature
    case invalidAddressFormat
    /// Firmware `Parsing signature failed - %s.`
    case parsingSignatureFailed(String)
    /// Firmware `Invalid signature for msg - %s.`
    case invalidSignatureForMsg(String)
}

/// Firmware `verify_armored_signed_msg` story.
public struct ArmoredVerifyResult: Equatable, Sendable {
    public var title: String
    public var body: String
}

public struct SignedFileDigestMismatch: Equatable, Sendable {
    public var filename: String
    /// SHA-256 of the file currently on disk (`calc` in `msgsign.py`).
    public var calculated: String
    /// Digest recorded in the signed message (`got` in the firmware format string).
    public var expected: String
}

public struct SignedFileDigestProblem: Equatable, Sendable {
    public var mismatches: [SignedFileDigestMismatch]
    public var missing: [String]
}

public struct SignedBitcoinMessage: Equatable, Codable, Sendable {
    public let message: String
    public let address: String
    public let signatureBase64: String
    public let path: String

    public var armored: String {
        """
        -----BEGIN BITCOIN SIGNED MESSAGE-----
        \(message)
        -----BEGIN BITCOIN SIGNATURE-----
        \(address)
        \(signatureBase64)
        -----END BITCOIN SIGNATURE-----

        """
    }
}

public enum BitcoinMessageSigner {
    /// Firmware `ux_input_text` default `max_len=100`, used by `sign_with_own_address`
    /// (address explorer "sign with this key").
    public static let uxInputMaximumLength = 100

    /// Firmware `MSG_SIGNING_MAX_LENGTH` (`public_constants.py`): USB, SD, NFC, QR JSON,
    /// and notes "Sign Note Text". `validate_text_for_signing` uses this as its default.
    public static let maximumLength = 240

    public static func messageHash(_ message: String) -> Data {
        let prefix = Data("Bitcoin Signed Message:\n".utf8)
        let body = Data(message.utf8)
        var data = Data()
        data.appendVarInt(UInt64(prefix.count)); data.append(prefix)
        data.appendVarInt(UInt64(body.count)); data.append(body)
        return SHA2.doubleSHA256(data)
    }

    /// Firmware `validate_text_for_signing` in `shared/msgsign.py`.
    /// Default `maxLength` is `uxInputMaximumLength` (100) for the interactive own-address path.
    /// Pass `maximumLength` (240) for USB / file / NFC / JSON / notes.
    /// Length is ASCII byte length after `to_ascii_printable`, not Swift `Character` count.
    public static func validate(_ text: String, allowTabAndNewline: Bool = false,
                                maxLength: Int = uxInputMaximumLength) throws -> String {
        let result = try toASCIIPrintable(text, allowTabAndNewline: allowTabAndNewline)
        let length = result.utf8.count
        guard length >= 2 else { throw MessageSigningError.tooShort }
        guard length <= maxLength else { throw MessageSigningError.tooLong(maxLength) }
        guard !result.contains("   ") else { throw MessageSigningError.tooManySpaces }
        guard !result.hasPrefix(" ") else { throw MessageSigningError.leadingSpace }
        guard !result.hasSuffix(" ") else { throw MessageSigningError.trailingSpace }
        return result
    }

    /// Firmware `utils.to_ascii_printable`.
    public static func toASCIIPrintable(_ text: String, allowTabAndNewline: Bool = false) throws -> String {
        let printableError: MessageSigningError = allowTabAndNewline
            ? .mustBeAsciiPrintableTabOrNewline : .mustBeAsciiPrintable
        // `len(s) == len(s.encode())`: every code point must be a single UTF-8 byte.
        guard text.unicodeScalars.count == text.utf8.count else { throw printableError }
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if allowTabAndNewline {
                guard (32...126).contains(value) || value == 9 || value == 10 else { throw printableError }
            } else {
                guard (32...126).contains(value) else { throw printableError }
            }
        }
        return text
    }

    /// Firmware `addr_fmt_from_subpath`. Default is classic P2PKH.
    public static func addressType(fromSubpath subpath: String) -> AddressType {
        if subpath.hasPrefix("m/84") { return .nativeSegwit }
        if subpath.hasPrefix("m/49") { return .wrappedSegwit }
        return .legacy
    }

    public static func derivationPath(purpose: UInt32, coinType: UInt32, account: UInt32,
                                      change: UInt32, index: UInt32) throws -> DerivationPath {
        try DerivationPath("m/\(purpose)'/\(coinType)'/\(account)'/\(change)/\(index)")
    }

    public static func signedMessageFilename(forInputFilename filename: String) -> String {
        let name = (filename as NSString).lastPathComponent
        if let range = name.range(of: ".", options: .backwards) {
            return String(name[..<range.lowerBound]) + "-signed.txt"
        }
        return name + "-signed.txt"
    }

    public static func signatureFilename(forInputFilename filename: String) -> String {
        let name = (filename as NSString).lastPathComponent
        if let range = name.range(of: ".", options: .backwards) {
            return String(name[..<range.lowerBound]) + ".sig"
        }
        return name + ".sig"
    }

    /// Firmware `parse_addr_fmt_str` names used by `parse_msg_sign_request`.
    public static func addressType(fromAddrFmt fmt: String) -> AddressType? {
        switch fmt.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "p2pkh": .legacy
        case "p2wpkh": .nativeSegwit
        case "p2sh-p2wpkh", "p2wpkh-p2sh": .wrappedSegwit
        default: nil
        }
    }

    public struct SignRequest: Equatable, Sendable {
        public var message: String
        public var subpath: String
        public var addressType: AddressType
        /// Firmware JSON `msg_sign_request` sets `allow_tab_nl` from `is_json`.
        public var allowTabAndNewline: Bool = false
    }

    /// Firmware `decoders.decode_qr`: Sparrow `signmessage` or JSON object with a `msg` key.
    /// Generic 1–3 line text is `text`, not `smsg`.
    public static func isQRSignMessagePayload(_ data: String) -> Bool {
        if data.contains("signmessage") { return true }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            return false
        }
        return object["msg"] != nil
    }

    /// Firmware `ux_visualize_textqr`: truncate at `MSG_SIGNING_MAX_LENGTH` and omit (0) when longer.
    public static func simpleTextQRDisplay(_ text: String) -> (shown: String, canSign: Bool) {
        if text.count <= maximumLength { return (text, true) }
        return (String(text.prefix(maximumLength)) + "...", false)
    }

    /// Firmware `parse_msg_sign_request` in `shared/msgsign.py`.
    /// JSON that parses but has missing/null `msg` is a hard failure (`MSG required`);
    /// it must not fall through to newline-separated line parsing.
    public static func parseSignRequest(_ data: String) -> SignRequest? {
        // Sparrow: `data.split(" ", 2)` on the raw payload (no trim, empty fields kept).
        if let sparrow = parseSparrowSignRequest(data) {
            return sparrow
        }
        let trimmed = data.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsedJSON = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) {
            return parseJSONSignRequest(parsedJSON)
        }
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        guard (1...3).contains(lines.count) else { return nil }
        let text = lines[0]
        let subpath = lines.count >= 2 ? lines[1] : ""
        let fmt = lines.count >= 3 ? lines[2] : ""
        let type = addressType(fromAddrFmt: fmt) ?? addressType(fromSubpath: subpath)
        return SignRequest(message: text, subpath: subpath, addressType: type)
    }

    /// Firmware Sparrow branch: `mark, subpath, *msg_line = data.split(" ", 2)`.
    private static func parseSparrowSignRequest(_ data: String) -> SignRequest? {
        guard data.contains("signmessage") else { return nil }
        let parts = data.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "signmessage", parts[2].hasPrefix("ascii:") else { return nil }
        let subpath = parts[1]
        return SignRequest(message: String(parts[2].dropFirst(6)), subpath: subpath,
                           addressType: addressType(fromSubpath: subpath))
    }

    /// Firmware JSON branch: only `ValueError` from `ujson.loads` falls through to lines.
    /// Missing/null `msg` is `AssertionError("MSG required")`.
    private static func parseJSONSignRequest(_ parsedJSON: Any) -> SignRequest? {
        guard let object = parsedJSON as? [String: Any] else { return nil }
        guard let text = object["msg"] as? String else { return nil }
        let subpath: String
        if let rawSubpath = object["subpath"] {
            guard let value = rawSubpath as? String else { return nil }
            subpath = value
        } else {
            subpath = ""
        }
        let fmt = object["addr_fmt"] as? String ?? ""
        let type = addressType(fromAddrFmt: fmt) ?? addressType(fromSubpath: subpath)
        return SignRequest(message: text, subpath: subpath, addressType: type, allowTabAndNewline: true)
    }

    public static func sign(_ message: String, root: HDKey, path: DerivationPath,
                            type: AddressType, deltaMode: Bool = false,
                            allowTabAndNewline: Bool = false) throws -> SignedBitcoinMessage {
        let key = try root.derived(path: path)
        guard let privateKey = key.privateKey else { throw MessageSigningError.missingPrivateKey }
        return try sign(message, privateKey: privateKey, publicKey: key.publicKey, type: type,
                        network: root.network, path: path.description, deltaMode: deltaMode,
                        allowTabAndNewline: allowTabAndNewline)
    }

    /// Firmware `approve_msg_sign(..., privkey=)` for WIF Store keys uses path `m`.
    public static func sign(_ message: String, privateKey: Data, publicKey: Data,
                            type: AddressType, network: BitcoinNetwork,
                            path: String = "m", validateText: Bool = true,
                            deltaMode: Bool = false, allowTabAndNewline: Bool = false) throws -> SignedBitcoinMessage {
        let text = validateText
            ? try validate(message, allowTabAndNewline: allowTabAndNewline, maxLength: maximumLength)
            : message
        guard type != .taproot else { throw MessageSigningError.unsupportedAddressType }
        var hash = messageHash(text)
        if deltaMode {
            // Firmware `msgsign.py`: silently invalidate signatures under the Delta PIN.
            hash = SHA2.doubleSHA256(hash)
        }
        let signature = try Secp256k1.sign(hash: hash, privateKey: privateKey)
        let baseHeader: UInt8
        switch type {
        case .legacy: baseHeader = 31
        case .wrappedSegwit: baseHeader = 35
        case .nativeSegwit: baseHeader = 39
        case .taproot: throw MessageSigningError.unsupportedAddressType
        }
        var compact = Data([baseHeader + signature.recoveryID])
        compact.append(signature.r); compact.append(signature.s)
        return SignedBitcoinMessage(message: text,
                                    address: try BitcoinAddress.address(publicKey: publicKey, type: type, network: network),
                                    signatureBase64: compact.base64EncodedString(), path: path)
    }

    /// Firmware `make_signature_file_msg`: `hex(hash) + "  " + filename` lines.
    public static func fileHashMessage(hashesAndNames: [(Data, String)]) -> String {
        hashesAndNames.map { $0.0.hexString + "  " + $0.1 }.joined(separator: "\n")
    }

    /// Firmware `parse_signature_file_msg`: hex digest, two spaces, filename.
    public static func parseFileHashMessage(_ message: String) -> [(digest: String, filename: String)]? {
        var result: [(String, String)] = []
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines where !line.isEmpty {
            let parts = line.split(separator: "  ", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].count == 64,
                  let digest = try? Data(hex: String(parts[0])), digest.count == 32 else { return nil }
            result.append((String(parts[0]).lowercased(), String(parts[1])))
        }
        return result.isEmpty ? nil : result
    }

    /// Firmware `parse_armored_signature_file`.
    public static func parseArmored(_ contents: String) throws -> (message: String, address: String, signature: String) {
        let sep = "-----"
        let dashCount = contents.components(separatedBy: sep).count - 1
        guard dashCount == 6 else {
            throw MessageSigningError.malformedSignatureFile(
                "Armor text MUST be surrounded by exactly five (5) dashes. msgsign.py:34"
            )
        }
        let parts = contents.components(separatedBy: sep)
        guard parts.count >= 5 else {
            throw MessageSigningError.malformedSignatureFile("msgsign.py:36")
        }
        let message = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let addrSig = parts[4].trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = addrSig.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count == 2 else {
            let detail = tokens.count < 2
                ? "not enough values to unpack (expected 2, got \(tokens.count))"
                : "too many values to unpack (expected 2)"
            throw MessageSigningError.malformedSignatureFile("\(detail) msgsign.py:39")
        }
        return (message, tokens[0], tokens[1])
    }

    /// Firmware `verify_signature`. Returns a warning string (possibly empty).
    public static func verify(message: String, address: String, signatureBase64: String) throws -> String {
        let compact: Data
        do {
            guard let decoded = Data(base64Encoded: signatureBase64, options: [.ignoreUnknownCharacters]),
                  decoded.count == 65 else {
                throw MessageSigningError.parsingSignatureFailed("invalid encoding")
            }
            compact = decoded
        }

        let header = compact[0]
        let (addrFmtBase, hash160, scriptHash): (UInt8, Data?, Data?)
        do {
            (addrFmtBase, hash160, scriptHash) = try addressTarget(address)
        } catch let error as MessageSigningError {
            throw error
        }

        // BIP-137: warn when the header is not rec_id + sig_hdr_base(addr_fmt).
        var warning = ""
        if !((0...3).contains(Int(header) - Int(addrFmtBase))) {
            warning = "Specified address format does not match signature header byte format."
        }

        // Recid is the low two bits of (header - 27); ngu recovers from a 31+rec_id header.
        let recID = (header &- 27) & 0x03
        var normalized = compact
        normalized[0] = 31 + recID
        let pubkey: Data
        do {
            pubkey = try Secp256k1.recoverPublicKey(hash: messageHash(message), compactSignature: normalized)
        } catch {
            throw MessageSigningError.invalidSignatureForMsg(String(describing: error))
        }
        let recHash160 = BitcoinHash.hash160(pubkey)
        if let scriptHash {
            let target = BitcoinHash.hash160(Data([0x00, 0x14]) + recHash160)
            guard target == scriptHash else { throw MessageSigningError.invalidSignature }
        } else if let hash160 {
            guard recHash160 == hash160 else { throw MessageSigningError.invalidSignature }
        }
        return warning
    }

    /// Firmware `verify_armored_signed_msg`. `fileBytes` is the CardSlot/Documents lookup.
    public static func verifyArmoredSignedMessage(
        _ contents: String,
        digestCheck: Bool = true,
        formatAddress: @escaping (String) -> String = { $0 },
        fileBytes: @escaping (String) -> Data? = { _ in nil }
    ) -> ArmoredVerifyResult {
        let parsed: (message: String, address: String, signature: String)
        do {
            parsed = try parseArmored(contents)
        } catch {
            return ArmoredVerifyResult(title: "FAILURE", body: error.localizedDescription)
        }

        let sigWarn: String
        do {
            sigWarn = try verify(message: parsed.message, address: parsed.address,
                                 signatureBase64: parsed.signature)
        } catch {
            return ArmoredVerifyResult(title: "ERROR", body: error.localizedDescription)
        }

        var title = "CORRECT"
        var warnMsg = ""
        var errMsg = ""
        var story = "Good signature by address:\n\(formatAddress(parsed.address))"

        if digestCheck, let problem = verifySignedFileDigest(parsed.message, fileBytes: fileBytes) {
            if !problem.missing.isEmpty {
                title = "WARNING"
                let base = "not present. Contents verification not possible."
                if problem.missing.count == 1 {
                    warnMsg = "'\(problem.missing[0])' is \(base)"
                } else {
                    warnMsg = "Files:\n" + problem.missing.map { "> \($0)" }.joined(separator: "\n")
                    warnMsg += "\nare \(base)"
                }
            }
            if !problem.mismatches.isEmpty {
                title = "ERROR"
                errMsg = problem.mismatches.map { item in
                    "Referenced file '\(item.filename)' has wrong contents.\nGot:\n\(item.expected)\n\nExpected:\n\(item.calculated)"
                }.joined()
            }
        }

        if !sigWarn.isEmpty {
            story = "Correctly signed, but not by this Coldcard. \(sigWarn)"
        }

        let body = [errMsg, story, warnMsg].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return ArmoredVerifyResult(title: title, body: body)
    }

    /// Firmware `verify_signed_file_digest`. `nil` means the message is not a file-hash list.
    public static func verifySignedFileDigest(
        _ message: String,
        fileBytes: (String) -> Data?
    ) -> SignedFileDigestProblem? {
        guard let listed = parseFileHashMessage(message) else { return nil }
        var mismatches: [SignedFileDigestMismatch] = []
        var missing: [String] = []
        for item in listed {
            guard let data = fileBytes(item.filename) else {
                missing.append(item.filename)
                continue
            }
            let digest = SHA2.sha256(data).hexString
            if digest != item.digest {
                mismatches.append(SignedFileDigestMismatch(filename: item.filename,
                                                           calculated: digest,
                                                           expected: item.digest))
            }
        }
        return SignedFileDigestProblem(mismatches: mismatches, missing: missing)
    }

    /// Firmware address decoding in `verify_signature`.
    private static func addressTarget(_ address: String) throws -> (base: UInt8, hash160: Data?, scriptHash: Data?) {
        if address.first == "1" || address.first == "m" || address.first == "n" {
            guard let decoded = try? Base58.checkDecode(address), decoded.count == 21 else {
                throw MessageSigningError.invalidSignature
            }
            return (31, Data(decoded.dropFirst()), nil)
        }
        if address.hasPrefix("bc1q") || address.hasPrefix("tb1q") || address.hasPrefix("bcrt1q") {
            if address.count > 44 { throw MessageSigningError.invalidAddressFormat }
            guard let decoded = try? Bech32.decodeSegwit(address), decoded.version == 0 else {
                throw MessageSigningError.invalidSignature
            }
            return (39, decoded.program, nil)
        }
        if address.first == "3" || address.first == "2" {
            guard let decoded = try? Base58.checkDecode(address), decoded.count == 21 else {
                throw MessageSigningError.invalidSignature
            }
            return (35, nil, Data(decoded.dropFirst()))
        }
        throw MessageSigningError.invalidAddressFormat
    }
}
