//
//  SwitchboardMenuBar.swift
//  Switchboard
//
//  The command center proper. The shelf widget is the glance; this is the list
//  you actually work from.
//

import DroppyKit
import SwiftUI

extension SwitchboardDroplet: MenuBarExtraProviding {
    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        MenuBarExtraDescriptor(
            title: "Switchboard",
            systemImage: "dot.radiowaves.left.and.right"
        ) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SwitchboardMenu(droplet: self, store: self.store))
        }
    }
}

private struct SwitchboardMenu: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore

    var body: some View {
        if store.services.isEmpty {
            Text("No services")
            Divider()
        } else {
            ForEach(store.services) { service in
                Menu(label(for: service)) {
                    if let url = service.url {
                        Button("Open \(url.absoluteString)") { droplet.open(url) }
                    }

                    if service.origin == .companion {
                        Button("Show log") { droplet.showLogs(for: service) }
                    }

                    if service.actions.isEmpty {
                        // A portless-only row. Say why it cannot be controlled
                        // rather than showing dead buttons.
                        Text("Read only — not in the companion's config")
                    } else {
                        if service.status == .running {
                            if service.actions.contains(.restart) {
                                Button("Restart") { store.perform("restart", on: service) }
                            }
                            if service.actions.contains(.stop) {
                                Button("Stop") { store.perform("stop", on: service) }
                            }
                        } else if service.actions.contains(.start) {
                            Button("Start") { store.perform("start", on: service) }
                        }
                    }
                }
            }
            Divider()
        }

        if !store.companionReachable {
            Text("Companion not running — read only")
        }
        if !store.proxyRunning {
            Text("portless proxy is down")
        }

        Button("Refresh") { droplet.refresh() }
        Button("Switchboard settings…") { droplet.openSettings() }
    }

    private func label(for service: Service) -> String {
        let mark = service.status == .running ? "●" : "○"
        if let port = service.port {
            return "\(mark)  \(service.name)   :\(port)"
        }
        return "\(mark)  \(service.name)"
    }
}
