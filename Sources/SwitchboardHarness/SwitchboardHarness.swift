// Deliberately not `main.swift`, which cannot coexist with `@main`.

import DroppyKit
import DroppyKitHarness
import Switchboard

@main
struct SwitchboardHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { SwitchboardDroplet() }
}
