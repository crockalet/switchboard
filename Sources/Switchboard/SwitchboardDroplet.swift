//
//  SwitchboardDroplet.swift
//  Switchboard
//

import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(SwitchboardPrincipal)
public final class SwitchboardPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { SwitchboardDroplet() }
}

/// Switchboard: the local dev services command center.
@MainActor
public final class SwitchboardDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "switchboard"

    enum PreferenceKey {
        static let companionPort = "companionPort"
        static let refreshInterval = "refreshInterval"
    }

    public let store = SwitchboardStore()
    public let logTail = LogTail(client: CompanionClient())
    // Not private: the HUD extension presents through it.
    var host: DropletHost?
    private var cancellables: Set<AnyCancellable> = []

    public func activate(host: DropletHost) throws {
        self.host = host

        let port = host.preferences.value(forKey: PreferenceKey.companionPort, default: CompanionClient.defaultPort)
        let interval = host.preferences.value(forKey: PreferenceKey.refreshInterval, default: 5.0)

        store.refreshInterval = interval
        store.companionPortChanged(to: port)
        logTail.clientChanged(to: CompanionClient(port: port))

        // Re-read the menu bar extra whenever the list changes, so its symbol
        // and title track what is actually running.
        store.$services
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // The store does the work; the droplet owns the presentation.
        store.announce = { [weak self] announcement in self?.announce(announcement) }

        store.start(log: host.log)
        host.log.info("Switchboard activated")
    }

    public func deactivate() {
        // Everything activate() started is torn down here. Swift cannot unload
        // code, so anything left running keeps running until Droppy relaunches.
        store.stop()
        logTail.stop()
        store.announce = nil
        cancellables.removeAll()
        host = nil
    }

    public func refresh() {
        Task { await store.refresh() }
    }

    // MARK: - Preferences

    var companionPort: Int {
        get { host?.preferences.value(forKey: PreferenceKey.companionPort, default: CompanionClient.defaultPort) ?? CompanionClient.defaultPort }
        set {
            host?.preferences.setValue(newValue, forKey: PreferenceKey.companionPort)
            store.companionPortChanged(to: newValue)
            logTail.clientChanged(to: CompanionClient(port: newValue))
        }
    }

    var refreshInterval: Double {
        get { host?.preferences.value(forKey: PreferenceKey.refreshInterval, default: 5.0) ?? 5.0 }
        set {
            host?.preferences.setValue(newValue, forKey: PreferenceKey.refreshInterval)
            store.refreshInterval = newValue
        }
    }

    func openSettings() {
        _ = host?.workspace.openSettings()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Opens the log takeover for one service. Only a companion row has a log:
    /// a portless route tells you a port is busy, not where its output went.
    func showLogs(for service: Service) {
        guard service.origin == .companion else { return }
        logTail.prepare(for: service)

        let presented = host?.notchSurface.presentExpandedSurface(
            ExpandedSurfacePresentationRequest(surfaceID: "switchboard.logs")
        )
        if presented == nil {
            host?.log.info("Switchboard: the host refused the log surface")
        }
    }

    func dismissLogs() {
        host?.notchSurface.dismissExpandedSurface("switchboard.logs")
    }
}
