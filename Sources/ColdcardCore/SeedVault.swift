import Foundation

/// Firmware `SeedVaultMenu` / `add_seed_to_vault` / `set_ephemeral_seed` (`seed.py`).
public enum SeedVaultMenuCopy {
    /// Firmware `'%2d: %s' % (i+1, rec.label)` (`seed.py` Seed Vault parent row).
    public static func parentRowLabel(index: Int, label: String) -> String {
        String(format: "%2d: %@", index + 1, label)
    }

    /// Firmware `rec.label` (vault stores `[XFP]` when unnamed).
    public static func storedLabel(custom: String, fingerprint: String) -> String {
        custom.isEmpty ? "[\(fingerprint.filter(\.isHexDigit))]" : custom
    }

    /// Firmware `ux_input_text(..., max_len=40)` on rename.
    public static let renameMaxLength = 40

    /// Firmware `actions.change_seed_vault` when seeds remain.
    public static let disableBlocked = "Please remove all seeds from the vault before disabling."

    /// Firmware `flow.py` Seed Vault `ToggleMenuItem` story.
    public static let enableStory = """
    Enable Seed Vault? Adds prompt to store temporary seeds into Seed Vault, where they can easily be reused later.

    WARNING: Seed Vault is encrypted (AES-256-CTR) by your seed, but not held directly inside secure elements. Backups are required after any change to vault! Recommended for experiments or temporary use.
    """

    /// Firmware `add_seed_to_vault` offer (`escape="1"`, `OK` is ENTER on Q).
    public static let offer = """
    Press (1) to store temporary seed into Seed Vault. This way you can easily switch to this secret and use it as temporary seed in future.

    Press ENTER to continue without saving.
    """

    /// `ux_show_story` body: name, master XFP, `SecretStash.summary(encoded[0])`, origin.
    public static func detailStory(label: String, xfp: String, encodedSecret: Data, origin: String) -> String {
        let secretType = SecretStash.summary(encodedSecret.first ?? 0)
        return "Name:\n\(label)\n\nMaster XFP: \(xfp)\nSecret Type: \(secretType)\n\nOrigin:\n\(origin)\n\n"
    }

    /// Firmware `title="[" + rec.xfp + "]"`.
    public static func deleteTitle(xfp: String) -> String {
        "[\(normalizedXFP(xfp))]"
    }

    /// Firmware `SeedVaultMenu._remove` body.
    public static func deleteStory(xfp: String, currentlyActive: Bool, ok: String = "ENTER") -> String {
        _ = xfp
        var message = "Remove seed from seed vault"
        if currentlyActive {
            message += "?\n\n"
        } else {
            message += " and delete its settings?\n\n"
            message += "Press \(ok) to continue, press (1) to only remove from seed vault and keep encrypted settings for later use.\n\n"
        }
        message += "WARNING: Funds will be lost if wallet is not backed-up elsewhere."
        return message
    }

    public static func savedStory(xfp: String) -> String {
        "[\(normalizedXFP(xfp))]\nSaved to Seed Vault"
    }

    /// Firmware `set_ephemeral_seed` `summarize_ux=True`.
    public static func ephemeralAppliedStory(bip39pw: String = "") -> String {
        var message = "New temporary master key is in effect now."
        if !bip39pw.isEmpty {
            message += "\n\nPassphrase: \(bip39pw)"
        }
        return message
    }

    public static func ephemeralAppliedTitle(xfp: String) -> String {
        "[\(normalizedXFP(xfp))]"
    }

    /// Firmware `add_seed_to_vault` skip rules before the offer story.
    public static func shouldOfferVault(
        enabled: Bool,
        secretBlank: Bool,
        deltaMode: Bool,
        hobbled: Bool,
        alreadyVaulted: Bool,
        newXFP: String,
        masterXFP: String
    ) -> Bool {
        guard enabled, !secretBlank, !deltaMode, !hobbled, !alreadyVaulted else { return false }
        return normalizedXFP(newXFP) != normalizedXFP(masterXFP)
    }

    public static func normalizedXFP(_ value: String) -> String {
        value.filter(\.isHexDigit).uppercased()
    }
}

/// Firmware BIP-39 passphrase limits and copy (`seed.py`, Q `ux_input_text`).
public enum BIP39Passphrase: Sendable {
    public static let maxLength = 100

    /// Firmware `ux_q1` footer when `b39_complete` and `scan_ok`.
    public static let inputHint = "TAB to auto-complete. QR to scan."

    /// Firmware `apply_pass_value` footer (`X`/`OK` are CANCEL/ENTER on Q).
    public static let applyFooter =
        "Press CANCEL to abort, ENTER to use the new wallet, (1) to apply and save to MicroSD for future."

    /// Simulator stand-in for firmware MicroSD `PassphraseSaver` (`pwsave.py`).
    public static let keychainStandIn =
        "This simulator stores saved passphrases in the device Keychain instead of a MicroSD file."

    public static func origin(parentXFP: String) -> String {
        "BIP-39 Passphrase on [\(SeedVaultMenuCopy.normalizedXFP(parentXFP))]"
    }

    /// Firmware `apply_pass_value`: `pa.tmp_value` chooses the parent-seed label.
    public static func parentSeedLabel(tmpActive: Bool, parentXFP: String) -> String {
        let xfp = SeedVaultMenuCopy.normalizedXFP(parentXFP)
        return tmpActive
            ? "current active temporary seed [\(xfp)]"
            : "master seed [\(xfp)]"
    }

    public static func isAllowedCharacter(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        return (32...126).contains(value.value)
    }

    public static func sanitized(_ value: String) -> String {
        String(value.filter(isAllowedCharacter).prefix(maxLength))
    }
}
