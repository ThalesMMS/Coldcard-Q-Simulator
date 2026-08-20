import Foundation

/// Firmware `Display.fullscreen` / `ux_dramatic_pause` titles (`ux.py`, `auth.py`, `seed.py`).
public enum FirmwareBusyTitle: Equatable, Sendable {
    public static let wait = "Wait..."
    public static let loading = "Loading..."
    public static let saving = "Saving..."
    public static let generating = "Generating..."
    public static let validating = "Validating..."
    public static let formatting = "Formatting..."
    public static let working = "Working..."
    public static let pickingKey = "Picking key..."
    public static let rendering = "Rendering..."
    public static let reading = "Reading..."
    public static let visualizing = "Visualizing..."
    public static let applying = "Applying..."
    public static let aborted = "Aborted."

    /// `ux_aborted` / `ux_dramatic_pause('Aborted.', 2)`.
    public static let abortedSeconds = 2.0
    /// `notes.py` / `multisig.py` `ux_dramatic_pause('Aborted.', 3)`.
    public static let abortedLongSeconds = 3.0
    /// `drv_entro.send_keystrokes` `ux_dramatic_pause("Aborted.", 1)`.
    public static let abortedKeystrokesSeconds = 1.0
}

/// Firmware `ToggleMenuItem.activate` (`menu.py:179-198`).
///
/// The explanatory story is shown **on entering the item**, only while the
/// setting is still the factory default. X (`ch == 'x'`) returns before the
/// chooser opens. `nvkey == "chain"` treats Bitcoin (`BTC`) as default.
public enum ToggleMenuStory: Equatable, Sendable {
    public static func showsStoryOnEnter(
        isChain: Bool = false,
        chainIsBitcoin: Bool = false,
        settingKeyMissing: Bool
    ) -> Bool {
        if isChain { return chainIsBitcoin }
        return settingKeyMissing
    }

    /// Firmware `actions.pushtx_setup_menu`: intro only while `ptxurl` is unset.
    public static func showsPushTxIntro(urlMissing: Bool) -> Bool {
        urlMissing
    }
}

/// Firmware `notes.GroupPickerMenu`: `(none)`, sorted groups, `New Group`,
/// with `MenuSystem(chosen=current)` (checkmark + cursor, no `"current"` subtitle).
public enum NoteGroupPickerUX: Equatable, Sendable {
    public static let noneTitle = "(none)"
    public static let newGroupTitle = "New Group"

    public static func sortedGroups(from groups: [String]) -> [String] {
        Array(Set(groups.filter { !$0.isEmpty })).sorted()
    }

    /// Index of the current group, or 0 for empty/`(none)`.
    public static func chosenIndex(current: String, groups: [String]) -> Int {
        let sorted = sortedGroups(from: groups)
        if current.isEmpty { return 0 }
        if let index = sorted.firstIndex(of: current) { return 1 + index }
        return 0
    }

    public static func isChecked(title: String, current: String) -> Bool {
        if title == noneTitle { return current.isEmpty }
        if title == newGroupTitle { return false }
        return !current.isEmpty && title == current
    }
}

/// Firmware `ux_q1.ux_visualize_txn`.
public enum VisualizeTransactionUX: Equatable, Sendable {
    public static let title = "Signed Transaction"
    public static let deserializeFailed = "Unable to deserialize"

    public static func body(inputs: Int, outputs: Int, txid: String) -> String {
        var msg = inputs == 1 ? "1 input, " : "\(inputs) inputs, "
        msg += outputs == 1 ? "1 output" : "\(outputs) outputs"
        msg += "\n\nTxid:\n" + txid
        return msg
    }
}
