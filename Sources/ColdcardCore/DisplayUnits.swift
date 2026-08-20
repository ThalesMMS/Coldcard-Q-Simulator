import Foundation

/// Firmware `value_resolution_chooser` / `rz` display units for Bitcoin amounts.
public enum DisplayUnits: String, Codable, CaseIterable, Sendable, Identifiable {
    case btc
    case mbtc
    case bits
    case sats

    public var id: String { rawValue }

    /// Firmware chooser labels are always BTC-family, regardless of chain.
    public var menuTitle: String {
        switch self {
        case .btc: "BTC"
        case .mbtc: "mBTC"
        case .bits: "bits"
        case .sats: "sats"
        }
    }

    /// Decimal places of 1 BTC, matching firmware `rz` values 8 / 5 / 2 / 0.
    public var btcDecimalPlaces: Int {
        switch self {
        case .btc: 8
        case .mbtc: 5
        case .bits: 2
        case .sats: 0
        }
    }

    /// Firmware `chains.render_value`: exact integer division, zero-padded, no grouping.
    public func format(_ satoshis: UInt64, network: BitcoinNetwork = .testnet,
                       unpad: Bool = false) -> String {
        let (text, unit) = render(satoshis, network: network, unpad: unpad)
        return "\(text) \(unit)"
    }

    public func render(_ satoshis: UInt64, network: BitcoinNetwork,
                       unpad: Bool = false) -> (String, String) {
        switch self {
        case .sats:
            return ("\(satoshis)", "sats")
        case .bits:
            return (formatted(satoshis, divisor: 100, width: 2, unpad: unpad), "bits")
        case .mbtc:
            return (formatted(satoshis, divisor: 100_000, width: 5, unpad: unpad), "m" + network.ticker)
        case .btc:
            return (formatted(satoshis, divisor: 100_000_000, width: 8, unpad: unpad), network.ticker)
        }
    }

    private func formatted(_ satoshis: UInt64, divisor: UInt64, width: Int, unpad: Bool) -> String {
        let whole = satoshis / divisor
        let frac = satoshis % divisor
        if unpad {
            if frac == 0 { return "\(whole)" }
            var fracText = String(repeating: "0", count: max(0, width - String(frac).count)) + String(frac)
            while fracText.last == "0" { fracText.removeLast() }
            return "\(whole).\(fracText)"
        }
        let fracText = String(repeating: "0", count: max(0, width - String(frac).count)) + String(frac)
        return "\(whole).\(fracText)"
    }
}

/// Firmware `max_fee_chooser` values. `-1` means no limit.
public enum MaxNetworkFee: Int, Codable, CaseIterable, Sendable, Identifiable {
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case unlimited = -1

    public var id: Int { rawValue }

    public var menuTitle: String {
        switch self {
        case .ten: "10% (default)"
        case .twentyFive: "25%"
        case .fifty: "50%"
        case .unlimited: "no limit"
        }
    }
}
