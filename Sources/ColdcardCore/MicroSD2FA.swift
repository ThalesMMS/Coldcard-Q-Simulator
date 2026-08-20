import Foundation

/// Firmware `pwsave.MicroSD2FA` — MicroSD (Documents file) as a second factor at login.
public enum MicroSD2FA {
    /// Simulator USB serial shown on View Identity (`Q-SIMULATOR`).
    public static let simulatorSerial = "Q-SIMULATOR"

    /// Stand-in for `CardSlot.get_id_hash()` (no physical SD CID on iOS).
    public static let documentsCardSalt = SHA2.sha256(Data("ccq-sim-documents-card".utf8))

    /// Firmware `stash.SensitiveValues.encryption_key` path (`m/2147431408h/0h`).
    public static let encryptionPath = "m/2147431408h/0h"

    public static let intro = "When enabled, this feature requires a specially prepared MicroSD card "
        + "to be inserted during login process. After correct PIN is provided, "
        + "if card slot is empty or unknown card present, the seed is wiped."

    public static let introQExtra = "If multiple SD cards are present during login, make sure that"
        + " authorized card is in the top slot (slot A)."

    public static let alreadyEnrolled = "Need a different MicroSD card. "
        + "This card would already be accepted."

    public static let checkFail = "This card would NOT be accepted during login."
    public static let checkPass = "This card is enrolled and would be accepted during login."
    public static let removeConfirm = "Remove this card from authorized set?"
    public static let needsCard = "Please insert a MicroSD card before attempting this operation."
    public static let saved = "Saved."
    public static let seedWipedTitle = "Seed Wiped"
    public static let seedWipedBody = "You must power cycle to continue."
    public static let checkFailTitle = "FAIL"
    public static let checkPassTitle = "PASS"

    public static func enrollConfirm(existingCount: Int) -> String {
        let ctx = existingCount >= 1 ? "this card or one of the others" : "it"
        return "Add this card to authorized set? Going forward \(ctx) must be "
            + "present during login process or the seed will be wiped!"
    }

    public static func introStory(includeQExtra: Bool) -> String {
        includeQExtra ? intro + "\n\n" + introQExtra : intro
    }

    public static func menuTitles(nonces: [String]) -> [String] {
        var titles = ["Add Card"]
        if !nonces.isEmpty {
            titles.append("Check Card")
            for index in nonces.indices {
                titles.append("Remove Card #\(index + 1)")
            }
        }
        return titles
    }

    /// Firmware `.{B2A(hmac(sha256(serial), b'silly?')[0:8])}.2fa`.
    public static func tokenFilename(serial: String = simulatorSerial) -> String {
        let key = SHA2.sha256(Data(serial.utf8))
        let digest = HMAC.sha256(key: key, message: Data("silly?".utf8))
        return ".\(Data(digest.prefix(8)).hexString).2fa"
    }

    public static func visibleTokenFilename(serial: String = simulatorSerial) -> String {
        String(tokenFilename(serial: serial).drop(while: { $0 == "." }))
    }

    public static func looksLikeTokenFilename(_ name: String) -> Bool {
        name.lowercased().hasSuffix(".2fa")
    }

    public static func nonceHex(from bytes: Data) -> String {
        precondition(bytes.count == 8)
        return bytes.hexString
    }

    /// Firmware `encryption_key`: SHA256(SHA256(salt || node.privkey || salt)).
    public static func encryptionKey(root: HDKey, salt: Data) throws -> Data {
        let node = try root.derived(path: DerivationPath(encryptionPath))
        guard let privateKey = node.privateKey else { throw BIP32Error.invalidKey }
        return SHA2.sha256(SHA2.sha256(salt + privateKey + salt))
    }

    /// AES-256-CTR of compact JSON `{"nonce":"..."}` (firmware `aes256ctr` + `ujson.dumps`).
    public static func sealToken(nonce: String, key: Data) throws -> Data {
        let json = Data("{\"nonce\":\"\(nonce)\"}".utf8)
        return AES256CTR.crypt(key: key, data: json)
    }

    public static func readNonce(from data: Data, key: Data) -> String? {
        guard key.count == AES256CTR.keySize, !data.isEmpty else { return nil }
        let clear = AES256CTR.crypt(key: key, data: data)
        guard let object = try? JSONSerialization.jsonObject(with: clear) as? [String: Any],
              let nonce = object["nonce"] as? String, !nonce.isEmpty else { return nil }
        return nonce
    }

    public static func authorizedCardPresent(fileData: Data?, enrolledNonces: [String], key: Data) -> Bool {
        guard let fileData, let nonce = readNonce(from: fileData, key: key) else { return false }
        return enrolledNonces.contains(nonce)
    }

    public enum LoginDecision: Equatable, Sendable {
        case proceed
        case wipe
    }

    public static func loginDecision(enrolledNonces: [String], authorized: Bool) -> LoginDecision {
        if enrolledNonces.isEmpty { return .proceed }
        return authorized ? .proceed : .wipe
    }

    public static func removing(_ nonce: String, from nonces: [String]) -> [String] {
        nonces.filter { $0 != nonce }
    }
}
