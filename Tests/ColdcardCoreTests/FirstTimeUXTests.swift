import Testing
@testable import ColdcardCore

@Test func firstTimeUXRunsWhenDuIsUnset() {
    #expect(FirstTimeUX.shouldRun(du: nil))
}

@Test func firstTimeUXDoesNotRunAfterDuIsWritten() {
    #expect(!FirstTimeUX.shouldRun(du: 1))
    #expect(!FirstTimeUX.shouldRun(du: 0))
}

@Test func firstTimeUXHardwareDefaultsMatchFirmware() {
    let fresh = FirstTimeUX.HardwarePorts(
        du: nil,
        usbEnabled: true,
        nfcEnabled: true,
        virtualDiskMode: 2
    )
    let applied = FirstTimeUX.applyHardwareDefaultsIfNeeded(fresh)
    #expect(applied?.du == 1)
    #expect(applied?.usbEnabled == false)
    #expect(applied?.nfcEnabled == false)
    #expect(applied?.virtualDiskMode == 0)
}

@Test func firstTimeUXDoesNotReplayWhenUSBIsReenabled() {
    var ports = FirstTimeUX.HardwarePorts(
        du: nil,
        usbEnabled: true,
        nfcEnabled: false,
        virtualDiskMode: 0
    )
    let first = FirstTimeUX.applyHardwareDefaultsIfNeeded(ports)
    #expect(first != nil)
    ports = first!
    ports.usbEnabled = true
    ports.du = FirstTimeUX.du(usbEnabled: true)
    #expect(ports.du == 0)
    #expect(FirstTimeUX.applyHardwareDefaultsIfNeeded(ports) == nil)
    #expect(ports.usbEnabled)
    #expect(!ports.nfcEnabled)
    #expect(ports.virtualDiskMode == 0)
}

@Test func firstTimeUXWelcomeCopyMatchesFirmware() {
    #expect(FirstTimeUX.welcomeTitle == "Welcome!")
    #expect(
        FirstTimeUX.story
            == "Your COLDCARD has been configured for best security practices: \n\n- USB disabled\n- NFC disabled\n- VirtDisk disabled\n\nYou can change these under Settings > Hardware On/Off."
    )
}

@Test func firstTimeUXRunsOnlyAfterASeedExists() {
    #expect(!FirstTimeUX.shouldPresent(hasSeed: false, du: nil))
    #expect(FirstTimeUX.shouldPresent(hasSeed: true, du: nil))
    #expect(!FirstTimeUX.shouldPresent(hasSeed: true, du: 1))
}
