import Foundation
import IOKit.pwr_mgt

/// "Keep awake": stops the display (and with it the Mac) from sleeping
/// until switched off — a power assertion, the same thing `caffeinate` uses.
@MainActor
final class KeepAwake: ObservableObject {

    static let shared = KeepAwake()

    @Published private(set) var isOn = false

    private var assertion = IOPMAssertionID(0)

    private init() {}

    func toggle() {

        if isOn {
            IOPMAssertionRelease(assertion)
            assertion = 0
            isOn = false
            return
        }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ARC — Keep Awake" as CFString,
            &assertion
        )

        isOn = result == kIOReturnSuccess
    }
}
