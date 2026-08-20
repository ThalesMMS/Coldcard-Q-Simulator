import Foundation

/// Firmware `address_explorer.py` layout helpers (Q keyboard, story, CSV, KeypathMenu).
public enum AddressExplorer {
    /// Firmware `wallet.MAX_BIP32_IDX`.
    public static let maxIndex: UInt32 = (1 << 31) - 1
    public static let pageSize: UInt32 = 10
    public static let csvDefaultCount: UInt32 = 250

    public enum Application: Sendable {
        case wasabi
        case samouraiPostmix
        case samouraiPremix
    }

    /// Firmware `show_n_addresses` LEFT/RIGHT paging (`:416-429`). Q maps Mk4 `7`/`9` to arrows.
    public static func move(start: UInt32, deltaPages: Int, n: UInt32 = pageSize) -> UInt32 {
        guard n > 0 else { return start }
        if deltaPages < 0 {
            if start < n {
                return start == 0 ? start : 0
            }
            return start - n
        }
        if deltaPages > 0 {
            if start > maxIndex &- n { return start }
            return start + n
        }
        return start
    }

    /// Firmware `KEY_HOME` (`:430-431`) — first address, not `self.start`.
    public static func homeStart(from _: UInt32 = 0) -> UInt32 { 0 }

    public static func visibleCount(start: UInt32, n: UInt32 = pageSize) -> UInt32 {
        guard start <= maxIndex else { return 0 }
        let last = min(start + n - 1, maxIndex)
        return last - start + 1
    }

    public static func header(start: UInt32, count: UInt32?) -> String {
        guard let count else { return "Showing single address." }
        let end = min(start + count - 1, maxIndex)
        return "Addresses \(start)⋯\(end):"
    }

    public static func row(derivation: String, address: String) -> String {
        "\(derivation) =>\n\(address)\n\n"
    }

    /// Firmware `key0` only when `allow_change and change == 0` (`:341`).
    public static func changeKeyLabel(allowChange: Bool, showingChange: Bool) -> String? {
        (allowChange && !showingChange) ? "to show change addresses" : nil
    }

    /// Firmware `n = 10 if 'idx' in path else None` (`:284-285`).
    public static func listCount(path: String) -> UInt32? {
        path.contains("idx") ? pageSize : nil
    }

    /// Firmware `PickAddrFmtMenu` (`:129-133`) against `chains.SINGLESIG_AF`.
    public static func formatPickerIndex(path: String) -> Int {
        if path.hasPrefix("m/44h") { return 1 }
        if path.hasPrefix("m/49h") { return 2 }
        return 0
    }

    public static func applicationPath(_ kind: Application, coinType: UInt32) -> String {
        switch kind {
        case .wasabi:
            "m/84h/\(coinType)h/0h/{change}/{idx}"
        case .samouraiPostmix:
            "m/84h/\(coinType)h/2147483646h/{change}/{idx}"
        case .samouraiPremix:
            "m/84h/\(coinType)h/2147483645h/{change}/{idx}"
        }
    }

    public static func csvCount(isSingle: Bool, start: UInt32, requested: UInt32 = csvDefaultCount) -> UInt32? {
        if isSingle { return nil }
        guard start <= maxIndex else { return 0 }
        let remaining = maxIndex - start + 1
        return min(requested, remaining)
    }

    /// Firmware `allow_qr = (not ms_wallet) or settings.get("msas", 0)` (`:295`).
    public static func allowQR(isMultisig: Bool, showFull: Bool) -> Bool {
        !isMultisig || showFull
    }

    /// Firmware `:319-322` — full signer paths only for address 0 when N ≤ 4.
    public static func multisigDerivationLine(idx: UInt32, change: UInt32, signerCount: Int, paths: [String]) -> String {
        if idx == 0, signerCount <= 4 {
            return paths.joined(separator: "\n") + "\n"
        }
        return "⋯/\(change)/\(idx)"
    }

    public static func story(
        isSingle: Bool,
        pageStart: UInt32,
        startIndex: UInt32,
        rows: [(String, String)],
        exportPrompt: String
    ) -> String {
        var msg = ""
        if isSingle {
            msg += "Showing single address.\n\n"
        } else {
            msg += header(start: pageStart, count: pageSize) + "\n\n"
        }
        for (deriv, address) in rows {
            msg += row(derivation: deriv, address: address)
        }
        if isSingle {
            msg += " Press (0) to sign message with this key."
        } else {
            if pageStart == startIndex, !exportPrompt.isEmpty {
                msg += exportPrompt + "\n\n"
            }
            msg += "Press RIGHT to see next group, LEFT to go back. X to quit."
        }
        return msg
    }

    /// Firmware `generate_address_csv` multisig header (`:444-446`).
    public static func multisigCSV(
        rows: [(index: UInt32, address: String, scriptHex: String, derivations: [String])],
        signerCount: Int
    ) -> String {
        var headers = ["Index", "Payment Address", "Redeem Script"]
        if signerCount > 0 {
            for i in 1...signerCount {
                headers.append("Derivation (\(i) of \(signerCount))")
            }
        }
        var lines = ["\"" + headers.joined(separator: "\",\"") + "\""]
        for row in rows {
            var line = "\(row.index),\"\(row.address)\",\"\(row.scriptHex)\",\""
            line += row.derivations.joined(separator: "\",\"")
            line += "\""
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Firmware `KeypathMenu` labels (`:38-68`).
    public static func keypathLabels(atRoot: Bool, cpath: String, leaf: UInt32, ranged: Bool) -> [String] {
        if atRoot {
            var labels = ["m/⋯", "m/44h/⋯", "m/49h/⋯", "m/84h/⋯", "m"]
            if ranged {
                labels += ["m/0/{idx}", "m/{idx}"]
            }
            return labels
        }
        let p = "\(cpath)/\(leaf)"
        var labels = ["\(p)h/⋯", "\(p)/⋯", "\(p)h", p]
        if ranged {
            labels += ["\(p)h/0/{idx}", "\(p)/0/{idx}", "\(p)h/{idx}", "\(p)/{idx}"]
        }
        return labels
    }

    /// Q truncation: `⋯` + slice from the slash before the last two components (`:71-80`).
    public static func displayedKeypathLabel(
        _ label: String,
        atRoot: Bool,
        cpath: String,
        leaf: UInt32,
        ranged: Bool = true
    ) -> String {
        let labels = keypathLabels(atRoot: atRoot, cpath: cpath, leaf: leaf, ranged: ranged)
        let maxWide = labels.map(\.count).max() ?? 0
        guard maxWide >= 32, !atRoot else { return label }
        let p = "\(cpath)/\(leaf)"
        guard let last = p.lastIndex(of: "/"),
              let prev = p[p.startIndex..<last].lastIndex(of: "/") else { return label }
        let from = p.distance(from: p.startIndex, to: prev)
        guard from < label.count else { return label }
        return "⋯" + String(label.dropFirst(from))
    }

    public static func displayedKeypathLabels(atRoot: Bool, cpath: String, leaf: UInt32, ranged: Bool) -> [String] {
        keypathLabels(atRoot: atRoot, cpath: cpath, leaf: leaf, ranged: ranged).map {
            displayedKeypathLabel($0, atRoot: atRoot, cpath: cpath, leaf: leaf, ranged: ranged)
        }
    }
}
