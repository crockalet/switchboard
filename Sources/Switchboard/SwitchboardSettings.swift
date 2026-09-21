//
//  SwitchboardSettings.swift
//  Switchboard
//

import DroppyKit
import SwiftUI

extension SwitchboardDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(SwitchboardSettingsPane(droplet: self, store: store))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Companion port", keywords: ["switchboard", "companion", "port", "agent"]),
            SettingsSearchEntry(title: "Refresh interval", keywords: ["switchboard", "refresh", "poll", "interval"])
        ]
    }
}

private struct SwitchboardSettingsPane: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore

    @State private var companionPort: Double = Double(CompanionClient.defaultPort)
    @State private var refreshInterval: Double = 5

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.md) {
            DropletSettingsCard {
                DropletControlRow(
                    title: "Services",
                    icon: "dot.radiowaves.left.and.right",
                    infoTip: "Read from portless's own route table. No companion needed."
                ) {
                    DropletValuePill(text: "\(store.runningCount) of \(store.services.count) running")
                }

                DropletSettingsDivider()

                DropletControlRow(
                    title: "portless proxy",
                    icon: "network"
                ) {
                    DropletValuePill(text: store.proxyRunning ? "Running" : "Not running")
                }

                DropletSettingsDivider()

                DropletControlRow(
                    title: "Companion CLI",
                    icon: "terminal",
                    infoTip: "Without it Switchboard is read only: it can show services but not start or stop them."
                ) {
                    DropletValuePill(text: store.companionReachable ? "Connected" : "Not running")
                }
            }

            if !store.companionReachable {
                SettingsInfoTip("Install switchboard-agent to start, stop and restart services. Until then the list is read only.")
            }

            DropletSettingsCard {
                DropletSliderRow(
                    title: "Companion port",
                    value: "\(Int(companionPort))",
                    binding: $companionPort,
                    // Narrow on purpose. The pill inside the row is
                    // click-to-type for an exact number, and a slider spanning
                    // all 64k ports is undraggable.
                    range: 1024...9999,
                    step: 1,
                    // Deferred to the end of the drag: every write rebuilds the
                    // client and refetches, which is not something to do on
                    // each scroll frame.
                    onEditingChanged: { editing in
                        if !editing { droplet.companionPort = Int(companionPort) }
                    }
                )

                DropletSettingsDivider()

                DropletSliderRow(
                    title: "Refresh interval",
                    value: "\(Int(refreshInterval))s",
                    binding: $refreshInterval,
                    range: 1...60,
                    step: 1,
                    onEditingChanged: { editing in
                        if !editing { droplet.refreshInterval = refreshInterval }
                    }
                )
            }

            if let error = store.lastError {
                SettingsInfoTip(error)
            }
        }
        .onAppear {
            companionPort = Double(droplet.companionPort)
            refreshInterval = droplet.refreshInterval
        }
    }
}
