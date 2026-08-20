import Foundation

/// Firmware `trick_pins.py` / `se2.h` trick-PIN flags and login evaluation.
public struct TrickPinFlags: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UInt16.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let wipe = TrickPinFlags(rawValue: 0x8000)
    public static let brick = TrickPinFlags(rawValue: 0x4000)
    public static let fakeOut = TrickPinFlags(rawValue: 0x2000)
    public static let wordWallet = TrickPinFlags(rawValue: 0x1000)
    public static let xprvWallet = TrickPinFlags(rawValue: 0x0800)
    public static let deltaMode = TrickPinFlags(rawValue: 0x0400)
    public static let reboot = TrickPinFlags(rawValue: 0x0200)
    public static let firmwareDefined = TrickPinFlags(rawValue: 0x0100)
    public static let blankWallet = TrickPinFlags(rawValue: 0x0080)
    public static let countdown = TrickPinFlags(rawValue: 0x0040)

    public var isSpendingPolicyUnlock: Bool { contains(.firmwareDefined) }
}

public enum TrickPins {
    public static let slotCount = 14
    public static let wrongPINCode = "!p"
    public static let spendingPolicyUnlockArg: UInt16 = 0x0001
    /// Firmware `stash.duress_root`: `m/2147431408h/0h/0h`.
    public static let legacyDuressPath = "m/2147431408h/0h/0h"

    public static func slotSpan(flags: TrickPinFlags) -> Int {
        if flags.contains(.xprvWallet) { return 3 }
        if flags.contains(.wordWallet) { return 2 }
        return 1
    }

    public static func bip85WordCount(arg: UInt16) -> Int {
        (Int(arg) / 1000) == 2 ? 12 : 24
    }

    public static func bip85Kind(arg: UInt16) -> BIP85Kind {
        bip85WordCount(arg: arg) == 12 ? .words12 : .words24
    }

    /// Firmware `validate_delta_pin`.
    public static func validateDeltaPIN(truePIN: String, proposed: String) -> (problem: String?, arg: UInt16) {
        let right = truePIN.replacingOccurrences(of: "-", with: "")
        let fake = proposed.replacingOccurrences(of: "-", with: "")
        if right.count != fake.count || right.dropLast(min(4, right.count)) != fake.dropLast(min(4, fake.count)) {
            let problem = """
            Trick PIN must be same length (\(right.count)) as true PIN and \
            up to last four digits can be different between true PIN and trick.
            """
            return (problem, 0)
        }
        var encoded: UInt16 = 0
        for i in 0..<4 {
            let rightIndex = right.index(right.endIndex, offsetBy: -(1 + i))
            let fakeIndex = fake.index(fake.endIndex, offsetBy: -(1 + i))
            if right[rightIndex] == fake[fakeIndex] {
                encoded |= 0xf << (i * 4)
            } else {
                let digit = UInt16(right[rightIndex].asciiValue ?? 0x30) - 0x30
                encoded |= digit << (i * 4)
            }
        }
        return (nil, encoded)
    }

    /// Firmware `TrickPinMenu` ordinal for "Add If Wrong": ANY / 2nd / 3rd / Nth.
    public static func wrongAttemptOrdinal(_ count: Int) -> String {
        let n = max(1, count)
        switch n {
        case 1: return "ANY"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// Firmware `lgto_map` labels, including leading alignment spaces.
    public static func countdownMenuLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Disabled"
        case 5: " 5 minutes"
        case 15: "15 minutes"
        case 30: "30 minutes"
        case 60: " 1 hour"
        case 120: " 2 hours"
        case 240: " 4 hours"
        case 480: " 8 hours"
        case 720: "12 hours"
        case 1440: "24 hours"
        case 2880: "48 hours"
        case 4320: " 3 days"
        case 10080: " 1 week"
        case 40320: "28 days later"
        default: "\(minutes) minutes"
        }
    }

    public static let countdownChoices: [(minutes: Int, label: String)] = [
        (5, " 5 minutes"), (15, "15 minutes"), (30, "30 minutes"),
        (60, " 1 hour"), (120, " 2 hours"), (240, " 4 hours"), (480, " 8 hours"),
        (720, "12 hours"), (1440, "24 hours"), (2880, "48 hours"),
        (3 * 1440, " 3 days"), (7 * 1440, " 1 week"), (28 * 1440, "28 days later")
    ]

    public static func defaultCountdownMinutes(loginSetting: Int) -> Int {
        loginSetting == 0 ? 60 : loginSetting
    }

    public static func bip85IndexBase(wordCount: Int) -> Int {
        wordCount == 12 ? 2000 : 1000
    }

    public static func constructDuressSecret(flags: TrickPinFlags, arg: UInt16, root: HDKey) throws -> (path: String, secret: Data)? {
        if flags.contains(.wordWallet) {
            let kind = bip85Kind(arg: arg)
            let words = bip85WordCount(arg: arg)
            let result = try BIP85.derive(root: root, kind: kind, index: UInt32(arg))
            let path = "BIP85(words=\(words), index=\(arg))"
            return (path, result.entropy)
        }
        if flags.contains(.xprvWallet) {
            let node = try root.derived(path: try DerivationPath(legacyDuressPath))
            guard let privateKey = node.privateKey else { throw BIP32Error.invalidKey }
            return (legacyDuressPath, node.chainCode + privateKey)
        }
        return nil
    }

    public static func wordEntropyLength(arg: UInt16) -> Int {
        bip85WordCount(arg: arg) == 24 ? 32 : 16
    }
}

public struct TrickPinSlot: Codable, Equatable, Sendable {
    public var pin: String
    public var flags: TrickPinFlags
    public var arg: UInt16
    public var xdata: Data
    public var slotNum: Int
    /// Firmware settings `tp` vs SE2: hidden pins still fire at login.
    public var hidden: Bool

    public init(pin: String, flags: TrickPinFlags, arg: UInt16 = 0, xdata: Data = Data(),
                slotNum: Int, hidden: Bool = false) {
        self.pin = pin
        self.flags = flags
        self.arg = arg
        self.xdata = xdata
        self.slotNum = slotNum
        self.hidden = hidden
    }

    public var span: Int { TrickPins.slotSpan(flags: flags) }

    public var isWrongCatchall: Bool { pin == TrickPins.wrongPINCode }

    public var isDuressWallet: Bool { flags.contains(.wordWallet) || flags.contains(.xprvWallet) }

    public var isDelta: Bool { flags.contains(.deltaMode) }

    public var isSpendingPolicyUnlock: Bool {
        flags.contains(.firmwareDefined) && arg == TrickPins.spendingPolicyUnlockArg
    }

    public var recordedArg: UInt16 {
        flags.contains(.deltaMode) ? 0xffff : arg
    }

    public func wordEntropy() -> Data {
        Data(xdata.prefix(TrickPins.wordEntropyLength(arg: arg)))
    }

    public func xprvParts() -> (chainCode: Data, privateKey: Data)? {
        guard xdata.count >= 64 else { return nil }
        return (Data(xdata.prefix(32)), Data(xdata.dropFirst(32).prefix(32)))
    }
}

public enum TrickPinError: Error, Equatable, Sendable {
    case noSpaceLeft
    case pinInUse
    case unknownPIN
    case cannotHideDelta
}

public enum TrickWalletKind: Equatable, Sendable {
    case realSeed
    case blankAppearance
    case words(Data)
    case xprv(chainCode: Data, privateKey: Data)
}

/// Side effects the bootrom / `se2_test_trick_pin` plus mpy login apply for a matched slot.
public enum TrickLoginDecision: Equatable, Sendable {
    case notATrick
    /// `TC_FAKE_OUT`: pretend the PIN was wrong (after optional wipe).
    case fakeWrongPIN(wipeSeed: Bool)
    case brick(wipeSeed: Bool)
    case reboot(wipeSeed: Bool)
    /// `todo == TC_WIPE`: show wiped and lock up until a power cycle.
    case wipeLockup
    case login(TrickLoginSession)
}

public struct TrickLoginSession: Equatable, Sendable {
    public var flags: TrickPinFlags
    public var arg: UInt16
    public var wipeSeed: Bool
    public var wallet: TrickWalletKind
    public var countdownMinutes: Int?
    public var brickAfterCountdown: Bool
    public var spendingPolicyUnlock: Bool
    public var deltaMode: Bool

    public init(flags: TrickPinFlags, arg: UInt16, wipeSeed: Bool, wallet: TrickWalletKind,
                countdownMinutes: Int? = nil, brickAfterCountdown: Bool = false,
                spendingPolicyUnlock: Bool = false, deltaMode: Bool = false) {
        self.flags = flags
        self.arg = arg
        self.wipeSeed = wipeSeed
        self.wallet = wallet
        self.countdownMinutes = countdownMinutes
        self.brickAfterCountdown = brickAfterCountdown
        self.spendingPolicyUnlock = spendingPolicyUnlock
        self.deltaMode = deltaMode
    }
}

public struct TrickPinTable: Codable, Equatable, Sendable {
    public var slots: [TrickPinSlot]

    public init(slots: [TrickPinSlot] = []) {
        self.slots = slots
    }

    public var hasSpendingPolicyUnlock: Bool {
        slots.contains { !$0.hidden && $0.isSpendingPolicyUnlock }
    }

    public var hasDuressWallet: Bool {
        slots.contains { !$0.hidden && $0.isDuressWallet }
    }

    public func slot(forPIN pin: String, includeHidden: Bool = true) -> TrickPinSlot? {
        slots.first { $0.pin == pin && (includeHidden || !$0.hidden) }
    }

    /// Firmware `all_tricks`: sorted, `!p` last, optionally hiding the PIN used to log in.
    public func visiblePINs(hiding currentPIN: String?) -> [String] {
        var pins = slots.filter { !$0.hidden }.map(\.pin)
        if let currentPIN { pins.removeAll { $0 == currentPIN } }
        return pins.sorted { a, b in
            if a == TrickPins.wrongPINCode { return false }
            if b == TrickPins.wrongPINCode { return true }
            return a < b
        }
    }

    public func occupiedMask() -> UInt32 {
        var mask: UInt32 = 0
        for slot in slots {
            for offset in 0..<slot.span {
                let index = slot.slotNum + offset
                if index >= 0, index < TrickPins.slotCount {
                    mask |= 1 << index
                }
            }
        }
        return mask
    }

    public func availableSlots() -> [Int] {
        let used = occupiedMask()
        return (0..<TrickPins.slotCount).filter { used & (1 << $0) == 0 }
    }

    public func findEmptyStart(needed: Int) -> Int? {
        let avail = availableSlots()
        if needed <= 1 { return avail.first }
        for start in avail {
            if (0..<needed).allSatisfy({ avail.contains(start + $0) }) {
                return start
            }
        }
        return nil
    }

    public mutating func add(pin: String, flags: TrickPinFlags, arg: UInt16, xdata: Data = Data()) throws {
        if let existing = slot(forPIN: pin), existing.hidden {
            restore(pin: pin)
            return
        }
        if slot(forPIN: pin) != nil { throw TrickPinError.pinInUse }
        let needed = TrickPins.slotSpan(flags: flags)
        guard let start = findEmptyStart(needed: needed) else { throw TrickPinError.noSpaceLeft }
        slots.append(TrickPinSlot(pin: pin, flags: flags, arg: arg, xdata: xdata, slotNum: start, hidden: false))
    }

    @discardableResult
    public mutating func restore(pin: String) -> Bool {
        guard let index = slots.firstIndex(where: { $0.pin == pin }) else { return false }
        slots[index].hidden = false
        return true
    }

    public mutating func hide(pin: String) throws {
        guard let index = slots.firstIndex(where: { $0.pin == pin && !$0.hidden }) else {
            throw TrickPinError.unknownPIN
        }
        if slots[index].isDelta { throw TrickPinError.cannotHideDelta }
        slots[index].hidden = true
    }

    public mutating func delete(pin: String) {
        slots.removeAll { $0.pin == pin }
    }

    public mutating func changePIN(from oldPIN: String, to newPIN: String, arg: UInt16? = nil) throws {
        guard let index = slots.firstIndex(where: { $0.pin == oldPIN }) else {
            throw TrickPinError.unknownPIN
        }
        if newPIN != oldPIN, slot(forPIN: newPIN) != nil { throw TrickPinError.pinInUse }
        slots[index].pin = newPIN
        if let arg { slots[index].arg = arg }
    }

    public mutating func update(pin: String, flags: TrickPinFlags? = nil, arg: UInt16? = nil, xdata: Data? = nil) throws {
        guard let index = slots.firstIndex(where: { $0.pin == pin }) else {
            throw TrickPinError.unknownPIN
        }
        if let flags { slots[index].flags = flags }
        if let arg { slots[index].arg = arg }
        if let xdata { slots[index].xdata = xdata }
    }

    public mutating func clearAll() {
        slots.removeAll()
    }

    /// Firmware `check_new_main_pin`.
    public func checkNewMainPIN(_ pin: String) -> String? {
        if slot(forPIN: pin, includeHidden: true) != nil {
            return "That PIN is already in use as a Trick PIN."
        }
        for delta in slots where delta.isDelta {
            let (problem, _) = TrickPins.validateDeltaPIN(truePIN: pin, proposed: delta.pin)
            if problem != nil {
                return "That PIN value makes problems with a Delta Mode Trick PIN."
            }
        }
        return nil
    }

    /// Firmware `main_pin_has_changed`.
    public mutating func mainPINHasChanged(to newMainPIN: String) {
        for index in slots.indices where slots[index].isDelta {
            let (problem, arg) = TrickPins.validateDeltaPIN(truePIN: newMainPIN, proposed: slots[index].pin)
            if problem == nil {
                slots[index].arg = arg
            }
        }
    }

    /// Firmware `restore_backup`: drop clashes with the (new) true PIN and broken delta pins.
    public mutating func restoreFromBackup(values: [TrickPinSlot], truePIN: String) {
        slots.removeAll()
        for var slot in values {
            if slot.pin == truePIN { continue }
            if slot.isDelta {
                let (problem, arg) = TrickPins.validateDeltaPIN(truePIN: truePIN, proposed: slot.pin)
                if problem != nil { continue }
                slot.arg = arg
            }
            slot.hidden = false
            if self.slot(forPIN: slot.pin) == nil {
                slots.append(slot)
            }
        }
        compactSlotNumbers()
    }

    private mutating func compactSlotNumbers() {
        var cursor = 0
        for index in slots.indices {
            let span = slots[index].span
            if cursor + span > TrickPins.slotCount { break }
            slots[index].slotNum = cursor
            cursor += span
        }
    }

    /// Exact trick PIN (not `!p`). Mirrors `se2_test_trick_pin` then mpy login.
    public func decision(forPIN pin: String) -> TrickLoginDecision {
        guard pin != TrickPins.wrongPINCode, let slot = slot(forPIN: pin, includeHidden: true) else {
            return .notATrick
        }
        return Self.decision(for: slot, catchall: false)
    }

    /// Firmware `se2_handle_bad_pin`: after a PIN that matched neither true PIN nor a named trick.
    public func wrongPINDecision(failCount: Int) -> TrickLoginDecision {
        guard let slot = slot(forPIN: TrickPins.wrongPINCode, includeHidden: true) else {
            return .notATrick
        }
        if failCount < Int(slot.arg) { return .notATrick }
        return Self.decision(for: slot, catchall: true)
    }

    private static func decision(for slot: TrickPinSlot, catchall: Bool) -> TrickLoginDecision {
        let flags = slot.flags
        let wipe = flags.contains(.wipe)
        if flags.contains(.fakeOut) {
            return .fakeWrongPIN(wipeSeed: wipe)
        }
        if flags.contains(.countdown) {
            let minutes = Int(slot.arg == 0 ? 60 : slot.arg)
            let brickAfter = flags.contains(.brick)
            return .login(TrickLoginSession(
                flags: flags,
                arg: slot.arg,
                wipeSeed: wipe,
                wallet: .realSeed,
                countdownMinutes: minutes,
                brickAfterCountdown: brickAfter,
                spendingPolicyUnlock: slot.isSpendingPolicyUnlock
            ))
        }
        if flags.contains(.brick) {
            return .brick(wipeSeed: wipe)
        }
        if flags.contains(.reboot) {
            return .reboot(wipeSeed: wipe)
        }
        if flags == .wipe {
            return .wipeLockup
        }
        if catchall, wipe, !flags.contains(.wordWallet), !flags.contains(.xprvWallet),
           !flags.contains(.brick), !flags.contains(.reboot) {
            return .wipeLockup
        }

        let wallet: TrickWalletKind
        if flags.contains(.wordWallet) {
            wallet = .words(slot.wordEntropy())
        } else if flags.contains(.xprvWallet), let parts = slot.xprvParts() {
            wallet = .xprv(chainCode: parts.chainCode, privateKey: parts.privateKey)
        } else if flags.contains(.blankWallet) {
            wallet = .blankAppearance
        } else {
            wallet = .realSeed
        }

        return .login(TrickLoginSession(
            flags: flags,
            arg: slot.arg,
            wipeSeed: wipe,
            wallet: wallet,
            spendingPolicyUnlock: slot.isSpendingPolicyUnlock,
            deltaMode: flags.contains(.deltaMode)
        ))
    }

    public func uniquePINConflict(_ pin: String, currentPIN: String, excluding: String? = nil) -> Bool {
        if pin == currentPIN { return true }
        return slots.contains { $0.pin == pin && !$0.hidden && $0.pin != excluding }
    }

    public func forgottenPIN(matching pin: String) -> Bool {
        slots.contains { $0.pin == pin && $0.hidden }
    }
}

public enum TrickPinDetailKind: Equatable, Sendable {
    case duressWallet
    case blankWallet
    case countdown
    case pretendsWrong
    case deltaMode
    case unlockPolicy
    case wipesSeed
    case bricksCC
    case reboots

    public var menuTitle: String {
        switch self {
        case .duressWallet: "↳Duress Wallet"
        case .blankWallet: "↳Blank Wallet"
        case .countdown: "↳Countdown"
        case .pretendsWrong: "↳Pretends Wrong"
        case .deltaMode: "↳Delta Mode"
        case .unlockPolicy: "↳Unlock Policy"
        case .wipesSeed: "↳Wipes seed"
        case .bricksCC: "↳Bricks CC"
        case .reboots: "↳Reboots"
        }
    }

    public static func rows(for slot: TrickPinSlot) -> [TrickPinDetailKind] {
        var rows: [TrickPinDetailKind] = []
        if slot.isDuressWallet {
            rows.append(.duressWallet)
        } else if slot.flags.contains(.blankWallet) {
            rows.append(.blankWallet)
        } else if slot.flags.contains(.countdown) {
            rows.append(.countdown)
        } else if slot.flags.contains(.fakeOut) {
            rows.append(.pretendsWrong)
        } else if slot.flags.contains(.deltaMode) {
            rows.append(.deltaMode)
        } else if slot.isSpendingPolicyUnlock {
            rows.append(.unlockPolicy)
        }
        if slot.flags.contains(.wipe) { rows.append(.wipesSeed) }
        if slot.flags.contains(.brick) { rows.append(.bricksCC) }
        if slot.flags.contains(.reboot) { rows.append(.reboots) }
        return rows
    }
}
