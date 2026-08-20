import Foundation

/// Firmware `exceptions.SpendPolicyViolation` reasons (`ccc.py` `meets_policy`).
public enum SpendPolicyViolation: Error, Equatable, Sendable {
    case hasWarnings
    case magnitude
    case noLockTime
    case lockTimeNotHeight
    case rewound(UInt32)
    case velocity(UInt32)
    case whitelist(String)

    public var firmwareReason: String {
        switch self {
        case .hasWarnings: "has warnings"
        case .magnitude: "magnitude"
        case .noLockTime: "no nLockTime"
        case .lockTimeNotHeight: "nLockTime not height"
        case .rewound(let height): "rewound (\(height))"
        case .velocity(let height): "velocity (\(height))"
        case .whitelist(let address): "whitelist: " + address
        }
    }
}

public struct SpendingPolicyDecision: Equatable, Sendable {
    public var needsWeb2FA: Bool
    public init(needsWeb2FA: Bool) { self.needsWeb2FA = needsWeb2FA }
}

/// Snapshot of a PSBT for firmware `SpendingPolicy.meets_policy`.
public struct SpendingPolicyTransaction: Equatable, Sendable {
    public var outgoingSats: UInt64
    public var lockTime: UInt32
    public var nonChangeAddresses: [String]
    public var hasWarnings: Bool

    public init(outgoingSats: UInt64, lockTime: UInt32, nonChangeAddresses: [String], hasWarnings: Bool) {
        self.outgoingSats = outgoingSats
        self.lockTime = lockTime
        self.nonChangeAddresses = nonChangeAddresses
        self.hasWarnings = hasWarnings
    }
}

/// Firmware `SpendingPolicy` dict (`ccc.py`): same shape for SSSP (`sssp.pol`) and CCC (`ccc.pol`).
public struct SpendingPolicyLimits: Codable, Equatable, Sendable {
    public static let maxWhitelist = 25
    public static let nLockIsTime: UInt32 = 500_000_000

    public static let velocityLabels = [
        "Unlimited",
        "6 blocks (hour)",
        "24 blocks (4h)",
        "48 blocks (8h)",
        "72 blocks (12h)",
        "144 blocks (day)",
        "288 blocks (2d)",
        "432 blocks (3d)",
        "720 blocks (5d)",
        "1008 blocks (1w)",
        "2016 blocks (2w)",
        "3024 blocks (3w)",
        "4032 blocks (4w)"
    ]

    public static var velocityBlocks: [Int] {
        [0] + velocityLabels.dropFirst().compactMap { Int($0.split(separator: " ").first ?? "") }
    }

    public var mag: Int?
    public var vel: Int?
    public var blockH: UInt32?
    public var addresses: [String]
    public var web2fa: String

    public init(mag: Int? = nil, vel: Int? = nil, blockH: UInt32? = nil,
                addresses: [String] = [], web2fa: String = "") {
        self.mag = mag
        self.vel = vel
        self.blockH = blockH
        self.addresses = addresses
        self.web2fa = web2fa
    }

    public static func cccDefault(minBlock: UInt32) -> SpendingPolicyLimits {
        SpendingPolicyLimits(mag: 1, vel: 144, blockH: minBlock, addresses: [], web2fa: "")
    }

    public static func renderMagnitude(_ mag: Int) -> String {
        mag < 1000 ? "\(mag) BTC" : "\(mag) SATS"
    }

    public static func magnitudeSats(_ mag: Int) -> UInt64 {
        mag < 1000 ? UInt64(mag) * 100_000_000 : UInt64(mag)
    }

    /// Firmware `utils.cleanup_payment_address`.
    public static func cleanupPaymentAddress(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let _ = try? Base58.checkDecode(s), s.count < 40 { return s }
        if let _ = try? Bech32.decodeSegwit(s) { return s.lowercased() }
        return nil
    }

    /// Firmware `SpendingPolicy.meets_policy`. Returns whether web 2FA is required.
    public func evaluate(_ tx: SpendingPolicyTransaction, minBlock: UInt32) throws -> SpendingPolicyDecision {
        if tx.hasWarnings { throw SpendPolicyViolation.hasWarnings }

        if let mag {
            if tx.outgoingSats > Self.magnitudeSats(mag) { throw SpendPolicyViolation.magnitude }
        }

        if let vel, vel != 0 {
            if tx.lockTime == 0 { throw SpendPolicyViolation.noLockTime }
            if tx.lockTime >= Self.nLockIsTime { throw SpendPolicyViolation.lockTimeNotHeight }
            let blockH = max(self.blockH ?? 0, minBlock)
            if tx.lockTime <= blockH { throw SpendPolicyViolation.rewound(tx.lockTime) }
            if tx.lockTime < (blockH + UInt32(vel)) { throw SpendPolicyViolation.velocity(tx.lockTime) }
        }

        if !addresses.isEmpty {
            let allowed = Set(addresses)
            for address in tx.nonChangeAddresses where !allowed.contains(address) {
                throw SpendPolicyViolation.whitelist(address)
            }
        }

        return SpendingPolicyDecision(needsWeb2FA: !web2fa.isEmpty)
    }

    public mutating func noteSuccessfulSign(lockTime: UInt32) {
        if lockTime > 0, (lockTime < SpendingPolicyLimits.nLockIsTime), lockTime > (blockH ?? 1) {
            blockH = lockTime
        }
    }
}

public extension PSBT {
    func involvesMasterFingerprint(_ hex: String) -> Bool {
        let want = hex.filter(\.isHexDigit).uppercased()
        guard want.count == 8 else { return false }
        for map in inputs {
            for entry in map.all(type: 0x06) {
                guard let derivation = try? PSBTDerivation(entry: entry) else { continue }
                if derivation.masterFingerprint.hexString.uppercased() == want { return true }
            }
        }
        return false
    }
}

public extension PSBTReview {
    var spendingOutgoingSats: UInt64 {
        outputs.filter { !$0.isChange }.reduce(0) { $0 &+ $1.value }
    }

    var spendingNonChangeAddresses: [String] {
        outputs.filter { !$0.isChange }.map(\.address)
    }

    func spendingTransaction() -> SpendingPolicyTransaction {
        SpendingPolicyTransaction(
            outgoingSats: spendingOutgoingSats,
            lockTime: lockTime,
            nonChangeAddresses: spendingNonChangeAddresses,
            hasWarnings: !warnings.isEmpty
        )
    }
}
