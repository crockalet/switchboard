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
            SettingsSearchEntry(title: "Refresh interval", keywords: ["switchboard", "refresh", "poll", "interval"])
        ]
    }
}

/// Rooted in `DropletSettingsPane`, so Droppy mounts the sections in its own
/// grouped Form: the cards are the Form's sections and the rows its own rows,
/// with no divider placed by hand.
private struct SwitchboardSettingsPane: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore

    @State private var refreshInterval: Double = 5

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Status")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(
                        title: "Services",
                        icon: "dot.radiowaves.left.and.right",
                        infoTip: "Read from portless's own route table. No companion needed."
                    ) {
                        DropletValuePill(text: "\(store.runningCount) of \(store.services.count) running")
                    }

                    DropletControlRow(title: "portless proxy", icon: "network") {
                        DropletValuePill(text: store.proxyRunning ? "Running" : "Not running")
                    }

                    DropletControlRow(
                        title: "Companion CLI",
                        icon: "terminal",
                        infoTip: store.companionReachable
                            ? "Start, stop, restart and logs go through switchboard-agent."
                            : "Install switchboard-agent to start, stop and restart services. Until then the list is read only."
                    ) {
                        DropletValuePill(
                            text: store.companionReachable
                                ? "Connected on \(droplet.companionPort)"
                                : "Not running"
                        )
                    }

                    if let error = store.lastError {
                        DropletStackedRow(title: "Last error", icon: "exclamationmark.triangle") {
                            Text(error)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    DropletControlRow(title: "Check now", icon: "arrow.clockwise") {
                        Button("Refresh") { droplet.refresh() }
                    }
                }
            }

            DropletSettingsCard {
                DropletSliderRow(
                    title: "Refresh interval",
                    value: "\(Int(refreshInterval))s",
                    binding: $refreshInterval,
                    range: 1...60,
                    step: 1
                )
            }
        }
        .onAppear { refreshInterval = droplet.refreshInterval }
        // The pill takes typed values and arrow keys too, which never end a
        // drag, so save on every change rather than on release.
        .onChange(of: refreshInterval) { _, value in
            if value != droplet.refreshInterval { droplet.refreshInterval = value }
        }
    }
}
