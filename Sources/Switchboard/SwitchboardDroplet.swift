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
    private var isMenuOpen = false
    private var isSettingsVisible = false

    public func activate(host: DropletHost) throws {
        self.host = host

        store.refreshInterval = refreshInterval
        store.clientChanged = { [weak self] client in self?.logTail.clientChanged(to: client) }

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

        // Poll at the user's interval only while something shows the list.
        host.installState.statePublisher
            .sink { [weak self] _ in self?.updateWatched() }
            .store(in: &cancellables)
        host.shelf.didChange
            .sink { [weak self] in self?.updateWatched() }
            .store(in: &cancellables)

        store.start(log: host.log)
        updateWatched()
        host.log.info("Switchboard activated")
    }

    /// Safe after a partial activation, and while a refresh is in flight: the
    /// store drops any result that lands after `stop()`.
    public func deactivate() {
        store.stop()
        logTail.stop()
        store.announce = nil
        store.clientChanged = nil
        cancellables.removeAll()
        isMenuOpen = false
        isSettingsVisible = false
        // Re-enabling starts from the empty list, not a stale one.
        store.reset()
        widgetHeight = Self.cardHeight(rows: 0)
        host = nil
    }

    public func refresh() {
        Task { await store.refresh() }
    }

    // MARK: - Visibility

    private func updateWatched() {
        guard let host else { return }
        let onShelf = host.shelf.isExpanded
            && host.installState.state.activeWidgetIDs.contains(Self.widgetID)
        store.isWatched = onShelf || isMenuOpen || isSettingsVisible
    }

    func menuVisibilityChanged(_ isOpen: Bool) {
        isMenuOpen = isOpen
        updateWatched()
    }

    func settingsVisibilityChanged(_ isVisible: Bool) {
        isSettingsVisible = isVisible
        updateWatched()
    }

    // MARK: - Preferences

    /// Floored on read too: 1.0.0 builds before review stored down to 1s.
    var refreshInterval: Double {
        get {
            let stored = host?.preferences.value(forKey: PreferenceKey.refreshInterval, default: 5.0) ?? 5.0
            return max(stored, SwitchboardStore.minimumRefreshInterval)
        }
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
