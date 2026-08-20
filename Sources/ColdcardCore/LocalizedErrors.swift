import Foundation

extension ByteEncodingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHex: "Invalid hexadecimal encoding."
        case .outOfBounds: "Read past the end of the data."
        case .invalidVarInt: "Invalid CompactSize/varint."
        }
    }
}

extension BIP39Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidEntropyLength: "Invalid BIP-39 entropy length."
        case .invalidWordCount: "The seed phrase must contain 12, 15, 18, 21, or 24 words."
        case .unknownWord(let word): "‘\(word)’ is not in the English BIP-39 word list."
        case .invalidChecksum: "Invalid BIP-39 checksum."
        case .invalidSeedQR: "Invalid SeedQR content."
        }
    }
}

extension BIP32Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSeed: "The seed could not be converted into a valid BIP-32 master key."
        case .invalidKey: "Invalid BIP-32 key."
        case .invalidExtendedKey: "Invalid extended key."
        case .hardenedDerivationFromPublicKey: "Cannot perform hardened derivation from a public key."
        case .invalidChild: "Derivation produced an invalid child key."
        case .invalidPath(let path): "Invalid derivation path: \(path)."
        case .wrongNetwork: "The extended key belongs to a different Bitcoin network."
        }
    }
}

extension Base58Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidCharacter(let character): "Invalid Base58 character: \(character)."
        case .invalidChecksum: "Invalid Base58Check checksum."
        case .payloadTooShort: "The Base58Check payload is too short."
        }
    }
}

extension Bech32Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .mixedCase: "A Bech32 address cannot mix uppercase and lowercase characters."
        case .invalidCharacter: "Invalid Bech32 character."
        case .invalidChecksum: "Invalid Bech32/Bech32m checksum."
        case .invalidHRP: "Invalid HRP prefix."
        case .invalidData: "Invalid Bech32 data."
        case .invalidWitnessVersion: "Invalid witness version."
        case .invalidWitnessProgram: "Invalid witness program."
        }
    }
}

extension Secp256k1Error: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPrivateKey: "Invalid secp256k1 private key."
        case .invalidPublicKey: "Invalid secp256k1 public key."
        case .invalidHashLength: "The signing hash must be 32 bytes."
        case .signingFailed: "Unable to produce a valid secp256k1 signature."
        }
    }
}

extension BitcoinAddressError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPublicKey: "Invalid public key for address generation."
        case .unsupportedType: "This address type is not supported for this operation."
        }
    }
}

extension BitcoinTransactionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformed: "Malformed Bitcoin transaction."
        case .unsupportedSighash: "Unsupported SIGHASH type."
        case .inputIndexOutOfRange: "The input index is out of range."
        case .outputIndexOutOfRange: "The output index is out of range."
        }
    }
}

extension PSBTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidMagic: "Invalid PSBT header."
        case .malformed: "Malformed PSBT."
        case .missingUnsignedTransaction: "PSBT v0 does not contain the global unsigned transaction."
        case .unsupportedVersion(let version): "PSBT version \(version) is not supported; firmware accepts 0 or 2."
        case .mapCountMismatch: "The number of PSBT maps does not match its inputs and outputs."
        case .invalidUTXO: "The UTXO is missing, invalid, or incompatible with the transaction."
        case .noMatchingKey: "No wallet BIP-32 derivation matches this input."
        case .unsupportedInput: "This input type is not supported for signing."
        case .transactionMismatch: "The previous transaction does not match the specified outpoint."
        case .dangerousSighash(let sighash): String(format: "SIGHASH 0x%02X is blocked; only SIGHASH_ALL is allowed by default.", sighash)
        case .duplicateInput: "The PSBT contains the same outpoint in more than one input."
        case .pathTooDeep: "BIP-32 path is deeper than MAX_PATH_DEPTH (12)."
        case .tooComplex: PSBT.tooComplexStory
        case .checksumMismatch: PSBT.checksumMismatchStory
        case .oversize(let fileBytes, let maximum): PSBT.oversizeStory(fileBytes: fileBytes, maximum: maximum).body
        }
    }
}

extension WIFError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPayload, .invalidVersion, .invalidPrivateKey:
            "No valid WIF key found."
        case .uncompressedOnly: "compressed only"
        case .wrongNetwork: "chain"
        case .noValidKey(let duplicates):
            "No valid WIF key found." + (duplicates ? " Contains duplicate WIF(s)" : "")
        case .capacity(let attempted, let remaining):
            "Max \(WIF.maxStoreItems) items allowed in WIF Store.\n\nAttempted to import \(attempted) keys, while remaining WIF store capacity is only \(remaining). Please, make room first."
        }
    }
}

extension WalletExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedAddressType: "This address type is not supported by the exporter."
        }
    }
}

extension MessageSigningError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedAddressType: "This address format is not supported for compact message signing."
        case .missingPrivateKey: "The derived key does not contain private key material."
        case .mustBeAsciiPrintable: "must be ascii printable"
        case .mustBeAsciiPrintableTabOrNewline: "must be ascii printable, tab, or newline"
        case .tooShort: "msg too short (min. 2)"
        case .tooLong(let max): "msg too long (max. \(max))"
        case .tooManySpaces: "too many spaces together in msg(max. 3)"
        case .leadingSpace: "leading space(s) in msg"
        case .trailingSpace: "trailing space(s) in msg"
        case .malformedSignatureFile(let detail): "Malformed signature file. \(detail)"
        case .invalidSignature: "Invalid signature for message."
        case .invalidAddressFormat: "Invalid address format - must be one of p2pkh, p2sh-p2wpkh, or p2wpkh."
        case .parsingSignatureFailed(let reason): "Parsing signature failed - \(reason)."
        case .invalidSignatureForMsg(let reason): "Invalid signature for msg - \(reason)."
        }
    }
}

extension MultisigError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidScript: "need CHECKMULTISIG"
        case .invalidPolicy: "M/N range"
        case .badFormatLine: "bad format line"
        case .badDerivation: "bad derivation line"
        case .unableToParseXpub: "unable to parse xpub"
        case .wrongChain: "wrong chain"
        case .needFingerprint: "need fingerprint"
        case .emptyDerivation: "empty deriv"
        case .derivDepthMismatch: "deriv depth does not match xpub depth"
        case .wrongPubkey: "wrong pubkey"
        case .myKeyNotIncluded: "my key not included"
        case .myKeyIncludedMoreThanOnce: "my key included more than once"
        case .duplicateCosignerKey: "same key under two XFPs"
        case .isOurKey(let xfp): "[\(xfp)] is our key"
        case .nameInvalid: "name must be ascii, 1..20 long"
        case .unsortedNotAllowed: "Unsorted multisig \"multi(...)\" not allowed"
        case .missingXpubs: "need xpubs"
        case .wrongXpubCount: "wrong # of xpubs"
        case .unsupportedDescriptor: "Unsupported multisig descriptor."
        case .wrongChecksum: "wrong checksum"
        case .missingValue(let key): "'\(key)' key required"
        case .duplicateXFP: "dup XFP"
        case .xpubsDoNotMatchExisting: "XPUBs in PSBT do not match any existing wallet"
        case .myXFPNotInvolved: "My XFP not involved"
        case .invalidSignerCount: "Invalid number of signers,min is 2 max is \(maxMultisigSigners)."
        case .xpubMismatch: "xpub wrong"
        case .scriptValidation(let message): message
        }
    }
}

extension TapsignerBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKey: "Backup Password must be 32 hex digits"
        case .decryptionFailed: "Decryption failed - wrong key?"
        case .invalidPayload: "Expected HEX digits or Base64 encoded binary"
        }
    }
}

extension CloneTransferError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidStartFile: "Invalid ccbk-start.json"
        case .invalidCloneFilename: "Clone file not found."
        case .invalidPublicKey: "Invalid clone public key"
        }
    }
}

extension AESCTRError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKeyLength: "AES-CTR key must be 16 bytes."
        case .invalidNonceLength: "AES-CTR nonce must be 16 bytes."
        }
    }
}

extension AddressOwnershipError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidOnChain(let name): "That address is not valid on " + name
        case .walletNotDefined(let name): "Wallet '\(name)' not defined."
        case .noSuitableMultisig: "No suitable multisig wallets are currently defined."
        case .notFound(let candidates, let wallets):
            "Searched \(candidates) candidate addresses in \(wallets) wallet(s) without finding a match."
        }
    }
}

extension PushTxError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .tooBig: "Transaction is too large for NFC."
        case .invalidURL(let message): message
        case .notTransaction: "Not a Bitcoin transaction."
        case .notSeedWords: "Unable to find seed words"
        case .notAddressPath: "Expected address and derivation path."
        case .notBIP21: "Unable to find address from NFC data."
        case .invalidAddressFormat(let message): message
        case .notMultisig: "Unable to find multisig descriptor."
        }
    }
}
