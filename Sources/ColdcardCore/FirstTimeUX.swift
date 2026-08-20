import Foundation

/// Firmware `shared/ftux.py` `FirstTimeUX`.
///
/// Hardware runs this once while settings key `du` is unset. After FTUX,
/// `du=1` (USB off). Later USB "Default On" is stored as `du=0` so the key
/// stays present and Welcome is not shown again.
public enum FirstTimeUX {
    public static let welcomeTitle = "Welcome!"

    /// Exact `ux_show_story` body from `ftux.py` (trailing space after the colon).
    public static let story = "Your COLDCARD has been configured for best security practices: \n\n- USB disabled\n- NFC disabled\n- VirtDisk disabled\n\nYou can change these under Settings > Hardware On/Off."

    public struct HardwarePorts: Equatable, Sendable {
        /// Firmware settings `du`. `nil` means unset.
        public var du: Int?
        public var usbEnabled: Bool
        public var nfcEnabled: Bool
        public var virtualDiskMode: Int

        public init(du: Int?, usbEnabled: Bool, nfcEnabled: Bool, virtualDiskMode: Int) {
            self.du = du
            self.usbEnabled = usbEnabled
            self.nfcEnabled = nfcEnabled
            self.virtualDiskMode = virtualDiskMode
        }
    }

    /// `settings.get('du', None) is None`
    public static func shouldRun(du: Int?) -> Bool {
        du == nil
    }

    /// `goto_top_menu(first_time=True)` only after a seed exists (`actions.py`).
    public static func shouldPresent(hasSeed: Bool, du: Int?) -> Bool {
        hasSeed && shouldRun(du: du)
    }

    /// USB Port toggle: Disable USB → `du=1`; Default On → `du=0` (key kept).
    public static func du(usbEnabled: Bool) -> Int {
        usbEnabled ? 0 : 1
    }

    /// Force USB/NFC/VirtDisk off and write `du=1`. Returns `nil` if `du` is set.
    public static func applyHardwareDefaultsIfNeeded(_ ports: HardwarePorts) -> HardwarePorts? {
        guard shouldRun(du: ports.du) else { return nil }
        return HardwarePorts(du: 1, usbEnabled: false, nfcEnabled: false, virtualDiskMode: 0)
    }
}
