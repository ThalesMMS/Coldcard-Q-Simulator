import Foundation
import ColdcardCore

/// Factory mode (`flow.FactoryMenu`, `actions.make_top_menu`, `q1.scan_and_bag`).
///
/// Firmware `version.is_factory_mode` is bootrom RDP ≠ 2 (`callgate.get_factory_mode`);
/// the unix simulator analogue is launching with `-f`. iOS stand-in: persisted
/// `SimulatorPreferences.factoryModeFlag`, also written to UserDefaults key
/// `unix_factory_flag` (Settings.bundle toggle). A programmed bag number forces
/// factory mode off, matching `version.py`.
extension SimulatorStore {
    static let unixFactoryFlagDefaultsKey = "unix_factory_flag"
    static let seBagNumberDefaultsKey = "se_bag_number"
    static let settingsTestedDefaultsKey = "settings_tested"

    /// SE `callgate.get_bag_number()` — nil when unprogrammed (firmware `UNBAGGED!`).
    var displayedBagNumber: String? {
        let value = preferences.bagNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Firmware `version.is_factory_mode` after the bag-number override.
    var isFactoryMode: Bool {
        preferences.factoryModeFlag && displayedBagNumber == nil
    }

    func persistFactoryStandIn() {
        UserDefaults.standard.set(preferences.factoryModeFlag, forKey: Self.unixFactoryFlagDefaultsKey)
        if let bag = displayedBagNumber {
            UserDefaults.standard.set(bag, forKey: Self.seBagNumberDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.seBagNumberDefaultsKey)
        }
        UserDefaults.standard.set(preferences.tested, forKey: Self.settingsTestedDefaultsKey)
    }

    func applyFactoryStandInFromDefaults() {
        if UserDefaults.standard.object(forKey: Self.unixFactoryFlagDefaultsKey) != nil {
            preferences.factoryModeFlag = UserDefaults.standard.bool(forKey: Self.unixFactoryFlagDefaultsKey)
        }
        if let bag = UserDefaults.standard.string(forKey: Self.seBagNumberDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !bag.isEmpty {
            preferences.bagNumber = bag
        }
        if record == nil, UserDefaults.standard.object(forKey: Self.settingsTestedDefaultsKey) != nil {
            preferences.tested = UserDefaults.standard.bool(forKey: Self.settingsTestedDefaultsKey)
        }
        persistFactoryStandIn()
    }

    func refreshFactoryRootIfNeeded() {
        guard screen == .menu, menuStack.isEmpty else { return }
        switch currentMenu {
        case .factory, .virgin:
            if currentMenu != rootMenu {
                openMenu(rootMenu, remember: false)
            }
        default:
            break
        }
    }

    func showBagNumberStory(onConfirm: StoryConfirmAction? = nil) {
        let title = displayedBagNumber ?? FirmwareCopy.unbaggedTitle
        showStory(title: title, body: FirmwareCopy.bagNumberBody, onConfirm: onConfirm)
    }

    func beginFactoryBagMeNow() {
        // q1.scan_and_bag: tested + (blank PIN or factory mode).
        do {
            guard preferences.tested else { throw FactoryBagError.notTested }
            guard !hasPIN || isFactoryMode else { throw FactoryBagError.badMode }
        } catch {
            showStory(title: FirmwareCopy.cannotBagTitle, body: error.localizedDescription)
            return
        }
        pendingBagScan = true
        showScanner = true
    }

    func handleFactoryBagScan(_ text: String) -> ScanHandlingResult {
        let got = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if got.isEmpty {
            pendingBagScan = false
            return .complete
        }
        if !got.allSatisfy({ $0 >= "0" && $0 <= "9" }) || !(8...32).contains(got.count) {
            showStory(title: FirmwareCopy.badScanTitle, body: got, onConfirm: .resumeBagScan)
            return .complete
        }
        pendingBagScan = false
        commitFactoryBagNumber(got)
        return .complete
    }

    func beginFactoryShipWithoutBag() {
        showStory(title: "Are you SURE ?!?", body: FirmwareCopy.shipWithoutBagConfirm,
                  onConfirm: .shipWithoutBag)
    }

    func confirmFactoryShipWithoutBag() {
        back()
        commitFactoryBagNumber(FirmwareCopy.shipWithoutBagValue, shippedWithoutBag: true)
    }

    func beginFactoryDFU() {
        // `actions.start_dfu` → `callgate.enter_dfu(0)` (not reached). Unix prints
        // "Enter bootloader (DFU)" and hangs. State machine until power.
        history.removeAll()
        menuStack.removeAll()
        screen = .factoryDFU
        selectedMenuIndex = 0
    }

    func consumeFactoryLockupKey(_ key: HardwareKey) -> Bool {
        guard screen == .factoryBagged || screen == .factoryDFU else { return false }
        if key == .power {
            finishFactoryLockupReboot()
        }
        return true
    }

    func finishFactoryLockupReboot() {
        pendingBagScan = false
        history.removeAll()
        menuStack.removeAll()
        if record == nil {
            presentFirstBoot()
        } else {
            goToLockedRoot()
        }
    }

    func confirmFactoryStory(_ action: StoryConfirmAction) -> Bool {
        switch action {
        case .shipWithoutBag:
            confirmFactoryShipWithoutBag()
            return true
        case .resumeBagScan:
            back()
            pendingBagScan = true
            showScanner = true
            return true
        default:
            return false
        }
    }

    /// `callgate.set_bag_number` then RDP=2, genuine light, and factory lockup / ship logout.
    func commitFactoryBagNumber(_ value: String, shippedWithoutBag: Bool = false) {
        let encoded = Array(value.utf8)
        // callgate.set_bag_number: `assert 3 <= len(s) < 32`
        guard (3..<32).contains(encoded.count) else {
            Task { await dramaticPause("FAILED", seconds: 2) }
            return
        }
        preferences.bagNumber = value
        preferences.factoryModeFlag = false
        persistPreferencesQuietly()
        persistFactoryStandIn()
        if shippedWithoutBag {
            Task { @MainActor in
                await dramaticPause(FirmwareCopy.noBagDoneTitle, seconds: 1.5)
                finishFactoryLockupReboot()
            }
            return
        }
        history.removeAll()
        menuStack.removeAll()
        screen = .factoryBagged
        selectedMenuIndex = 0
    }
}

private enum FactoryBagError: LocalizedError {
    case notTested
    case badMode

    var errorDescription: String? {
        switch self {
        case .notTested: FirmwareCopy.cannotBagNotTested
        case .badMode: FirmwareCopy.cannotBagBadMode
        }
    }
}
