import Foundation

/// Firmware `actions.clear_seed`, `any_active_duress_ux`, and `convert_ephemeral_to_master`.
public enum SeedDanger: Sendable {
    public static let destroyFirstTitle = "Are you SURE ?!?"
    /// `ux_confirm` without `confirm_key` — ENTER confirms.
    public static let destroyFirstConfirmKey: String? = nil
    public static let destroyFirstBody =
        "Wipe seed words and reset wallet. All funds will be lost. You better have a backup of the seed words. All settings like multisig wallets are also wiped. Saved temporary seed settings and Seed Vault are lost. Trick PINs are also completely removed."

    public static let destroyAgainTitle = "AGAIN..."
    public static let destroyAgainConfirmKey = "4"
    /// Message passed to `ux_confirm(..., 'AGAIN...', confirm_key='4')` — the confirm key is not in the body.
    public static let destroyAgainBody = """
    Are you REALLY sure though???

    This action will certainly cause you to lose all funds associated with this wallet, unless you have a backup of the seed words and know how to import them into a new wallet.
    """

    public static let duressBlockBody =
        "You have one or more duress wallets defined under Trick PINs. Please empty them, and clear associated Trick PINs before continuing."

    /// Firmware `seed.clear_seed` `dis.fullscreen('Clearing...')` then `callgate.fast_wipe(True)`.
    public static let clearingTitle = "Clearing..."
    /// Firmware `ux_aborted` / `ux_dramatic_pause('Aborted.', 2)`.
    public static let abortedPause = "Aborted."

    public static let lockDownTitle = "Are you SURE ?!?"
    public static let lockDownConfirmKey = "4"

    /// Firmware `if not pa.hobbled_mode: any_active_duress_ux()`.
    public static func shouldBlockDestroyForDuress(hobbled: Bool, hasActiveDuress: Bool) -> Bool {
        !hobbled && hasActiveDuress
    }

    /// Firmware `convert_ephemeral_to_master` story before `ux_confirm` appends the confirm-key suffix.
    public static func lockDownStory(
        isPassphraseWallet: Bool,
        masterHasWords: Bool,
        currentHasWords: Bool
    ) -> String {
        let type = isPassphraseWallet ? "BIP-39 passphrase wallet" : "temporary seed"
        var message = "Convert currently used \(type) to master seed. Old master seed"
        if masterHasWords {
            message += " words themselves are erased forever, "
        } else {
            message += " is erased forever, "
        }
        message += "and its settings blanked. This action is destructive "
            + "and may affect funds, if any, on old master seed. "
            + "Make sure all duress wallets associated with previous "
            + "seed are deleted, otherwise they will be carried forward "
            + "without being properly generated from new master seed. "
            + "Saved temporary seed settings and Seed Vault are lost. "
        if isPassphraseWallet {
            message += "BIP-39 passphrase "
                + "is captured during this process and will be in effect "
                + "going forward, but the passphrase itself is erased "
                + "and unrecoverable. "
        }
        if !currentHasWords {
            message += "The resulting wallet cannot be used with any other passphrase. "
        }
        message += "A reboot is part of this process. "
        message += "PIN code, and \(type) funds are not affected."
        return message
    }

    /// Displayed lock-down story: firmware `ux_confirm(msg, confirm_key='4')` appends the suffix.
    public static func lockDownConfirmBody(
        isPassphraseWallet: Bool,
        masterHasWords: Bool,
        currentHasWords: Bool
    ) -> String {
        lockDownStory(
            isPassphraseWallet: isPassphraseWallet,
            masterHasWords: masterHasWords,
            currentHasWords: currentHasWords
        ) + uxConfirmSuffix(key: lockDownConfirmKey)
    }

    public static func uxConfirmSuffix(key: String) -> String {
        "\n\nPress (\(key)) to prove you read to the end of this message and accept all consequences."
    }
}
