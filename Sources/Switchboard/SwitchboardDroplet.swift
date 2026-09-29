//
//  SwitchboardDroplet.swift
//  Switchboard
//

import Combine
import DroppyKit
import SwiftUI

/// The loader's principal class. Keep it empty: it runs before the host is ready.
@objc(SwitchboardPrincipal)
public final class SwitchboardPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { SwitchboardDroplet() }
}

/// Switchboard: the local dev services command center.
@MainActor
public final class SwitchboardDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal the bundle and manifest `id`; otherwise the loader refuses it.
    public nonisolated static let id: DropletID = "switchboard"

    enum PreferenceKey {
        static let refreshInterval = "refreshInterval"
    }

    public let store = SwitchboardStore()
    public let logTail = LogTail(client: CompanionClient())
    var host: DropletHost?
    /// The widget's declared height, cached so the host re-reads the new value
    /// when it is told the layout changed.
    private(set) var widgetHeight = SwitchboardDroplet.cardHeight(rows: 0)
    private var cancellables: Set<AnyCancellable> = []

    public func activate(host: DropletHost) throws {
        self.host = host

        let interval = host.preferences.value(forKey: PreferenceKey.refreshInterval, default: 5.0)

        store.refreshInterval = interval
        store.companionPortChanged(to: companionPort)
        logTail.clientChanged(to: CompanionClient(port: companionPort))

        // Keep the menu bar symbol and title in step with the service list.
        store.$services
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // `$services` fires before the store changes, so the height is taken
        // from the new value rather than re-read from the store.
        store.$services
            .map { Self.cardHeight(rows: $0.count) }
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self, height != self.widgetHeight else { return }
                self.widgetHeight = height
                self.host?.shelf.invalidateLayout(for: Self.widgetID)
            }
            .store(in: &cancellables)

        store.announce = { [weak self] announcement in self?.announce(announcement) }

        store.start(log: host.log)
        host.log.info("Switchboard activated")
    }

    /// Safe after a partial activation, and while a refresh is in flight: the
    /// store drops any result that lands after `stop()`.
    public func deactivate() {
        store.stop()
        logTail.stop()
        store.announce = nil
        cancellables.removeAll()
        // Re-enabling starts from the empty list, not a stale one.
        store.reset()
        widgetHeight = Self.cardHeight(rows: 0)
        host = nil
    }

    public func refresh() {
        Task { await store.refresh() }
    }

    // MARK: - Preferences

    /// Read from the companion's config each time, so editing that file and
    /// restarting the agent is all it takes.
    var companionPort: Int { CompanionLocator.port() }

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

    /// Opens the log takeover; only a companion row knows where its log lives.
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
