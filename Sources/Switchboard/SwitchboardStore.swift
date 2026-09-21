//
//  SwitchboardStore.swift
//  Switchboard
//

import Combine
import DroppyKit
import Foundation

/// Everything the surfaces read, plus the refresh task cancelled in `stop()`.
@MainActor
public final class SwitchboardStore: ObservableObject {
    @Published public private(set) var services: [Service] = []
    @Published public private(set) var companionReachable = false
    @Published public private(set) var proxyRunning = false
    @Published public private(set) var lastError: String?

    /// Set by the droplet, which owns how an announcement is shown.
    public var announce: ((ActionAnnouncement) -> Void)?

    /// Seconds between refreshes. Stored, so the settings pane can change it.
    public var refreshInterval: TimeInterval = 5

    private let portless: PortlessSource
    private var companion: CompanionClient
    private var refreshTask: Task<Void, Never>?
    private weak var log: (any DropletLogService)?

    public init(
        portless: PortlessSource = PortlessSource(),
        companionPort: Int = CompanionClient.defaultPort
    ) {
        self.portless = portless
        self.companion = CompanionClient(port: companionPort)
    }

    public func companionPortChanged(to port: Int) {
        companion = CompanionClient(port: port)
        Task { await refresh() }
    }

    // MARK: - Lifecycle

    public func start(log: (any DropletLogService)? = nil) {
        self.log = log
        stop()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.refreshInterval ?? 5
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Cancels the poller. Safe to call twice.
    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Refresh

    public func refresh() async {
        // Keep the list populated without the companion; probes go off-main.
        let source = portless
        let readOnly = await Task.detached { source.services() }.value
        let proxy = await Task.detached { source.proxyStatus() }.value

        var merged = readOnly
        var reachable = false

        do {
            let controllable = try await companion.services()
            reachable = true
            merged = Self.merge(portless: readOnly, companion: controllable)
            lastError = nil
        } catch CompanionError.notInstalled {
            // Not an error state: read-only is the designed fallback.
            reachable = false
        } catch {
            reachable = false
            lastError = "\(error)"
        }

        services = merged.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        companionReachable = reachable
        proxyRunning = proxy?.running ?? false
    }

    /// Prefer the controllable companion entry, but inherit the route's URL.
    static func merge(portless: [Service], companion: [Service]) -> [Service] {
        var result = companion
        let claimedPorts = Set(companion.compactMap(\.port))

        for route in portless where !claimedPorts.contains(route.port ?? -1) {
            result.append(route)
        }

        return result.map { service in
            guard service.origin == .companion, service.url == nil,
                  let port = service.port,
                  let match = portless.first(where: { $0.port == port })
            else { return service }

            return Service(
                id: service.id,
                name: service.name,
                url: match.url,
                port: service.port,
                pid: service.pid,
                origin: .companion,
                status: service.status,
                actions: service.actions
            )
        }
    }

    // MARK: - Actions

    public func perform(_ action: String, on service: Service) {
        guard service.origin == .companion else { return }
        let id = String(service.id.dropFirst("companion:".count))

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.companion.perform(action, on: id)
                await self.refresh()
                self.announce?(ActionAnnouncement(
                    symbol: Self.symbol(for: action),
                    headline: "\(service.name) \(Self.pastTense(of: action))"
                ))
            } catch CompanionError.refused(let message) {
                self.lastError = message
                self.log?.error("Switchboard: \(action) on \(id) refused — \(message)")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: "\(service.name) did not \(action)",
                    failure: message
                ))
            } catch {
                self.lastError = "The companion is not reachable."
                self.log?.error("Switchboard: \(action) on \(id) failed — \(error)")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: "\(service.name) did not \(action)",
                    failure: "The companion is not reachable."
                ))
            }
        }
    }

    static func symbol(for action: String) -> String {
        switch action {
        case "start": return "play.fill"
        case "stop": return "stop.fill"
        default: return "arrow.clockwise"
        }
    }

    static func pastTense(of action: String) -> String {
        switch action {
        case "start": return "started"
        case "stop": return "stopped"
        default: return "restarted"
        }
    }

    public var runningCount: Int {
        services.filter { $0.status == .running }.count
    }
}
