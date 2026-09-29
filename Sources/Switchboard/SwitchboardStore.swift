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
    /// The action in flight per service id, until the service reaches the
    /// state it asked for; the rows show progress instead of a stale control.
    @Published public private(set) var pending: [String: String] = [:]
    /// Why the last action on a service failed, for a few seconds. A HUD is
    /// not drawn over the open shelf, so the row itself has to say so.
    @Published public private(set) var failures: [String: String] = [:]

    /// Set by the droplet, which owns how an announcement is shown.
    public var announce: ((ActionAnnouncement) -> Void)?

    /// Seconds between refreshes. Stored, so the settings pane can change it.
    public var refreshInterval: TimeInterval = 5

    private let portless: PortlessSource
    private var companion: CompanionClient
    private var refreshTask: Task<Void, Never>?
    private var actionTasks: [UUID: Task<Void, Never>] = [:]
    private var failureTasks: [String: Task<Void, Never>] = [:]
    /// Bumped by every refresh and by `stop()`: a result is published only if
    /// nothing newer started, so a slow probe never overwrites a fresh one and
    /// nothing lands after the droplet is disabled.
    private var generation = 0
    private var isRunning = false
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
        isRunning = true
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.refreshInterval ?? 5
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Cancels the poller and every action in flight. Safe to call twice.
    public func stop() {
        isRunning = false
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        actionTasks.values.forEach { $0.cancel() }
        actionTasks.removeAll()
        pending.removeAll()
        failureTasks.values.forEach { $0.cancel() }
        failureTasks.removeAll()
        failures.removeAll()
    }

    /// Forgets what the last refresh saw, for a clean start after re-enabling.
    public func reset() {
        services = []
        companionReachable = false
        proxyRunning = false
        lastError = nil
    }

    // MARK: - Refresh

    public func refresh() async {
        guard isRunning else { return }
        generation += 1
        let token = generation

        // Keep the list populated without the companion; probes go off-main.
        let source = portless
        let readOnly = await Task.detached { source.services() }.value
        let proxy = await Task.detached { source.proxyStatus() }.value

        var merged = readOnly
        var reachable = false
        var error: String?

        do {
            let controllable = try await companion.services()
            reachable = true
            merged = Self.merge(portless: readOnly, companion: controllable)
        } catch CompanionError.notInstalled {
            // Not an error state: read-only is the designed fallback.
            reachable = false
        } catch let failure {
            reachable = false
            error = "The companion answered with something Switchboard cannot read: \(failure)"
        }

        // Disabled, or overtaken by a newer refresh, while this one waited.
        guard token == generation, isRunning else { return }

        lastError = error
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
        // A second press while one is in flight would start or restart twice.
        guard isRunning, service.origin == .companion, pending[service.id] == nil else { return }
        clearFailure(service.id)
        let id = String(service.id.dropFirst("companion:".count))
        let key = UUID()
        let companion = self.companion
        pending[service.id] = action

        actionTasks[key] = Task { [weak self] in
            defer {
                self?.actionTasks[key] = nil
                self?.pending[service.id] = nil
            }
            do {
                try await companion.perform(action, on: id)
                // Disabled while the companion worked: say nothing.
                guard let self, !Task.isCancelled else { return }
                await self.settle(service.id, after: action)
                guard !Task.isCancelled else { return }
                self.announce?(ActionAnnouncement(
                    symbol: Self.symbol(for: action),
                    headline: "\(service.name) \(Self.pastTense(of: action))"
                ))
            } catch CompanionError.refused(let message) {
                guard let self, !Task.isCancelled else { return }
                self.showFailure(message, on: service.id)
                self.lastError = message
                self.log?.error("Switchboard: \(action) on \(id) refused — \(message)")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: "\(service.name) did not \(action)",
                    failure: message
                ))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.showFailure("The companion is not reachable.", on: service.id)
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

    private func showFailure(_ message: String, on serviceID: String) {
        failures[serviceID] = message
        failureTasks[serviceID]?.cancel()
        failureTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.clearFailure(serviceID)
        }
    }

    private func clearFailure(_ serviceID: String) {
        failureTasks[serviceID]?.cancel()
        failureTasks[serviceID] = nil
        failures[serviceID] = nil
    }

    /// Refreshes until the service shows the state `action` leads to, for up
    /// to ten seconds: a restart passes through stopped, and a process can
    /// take a moment to bind its port.
    private func settle(_ serviceID: String, after action: String) async {
        let target: ServiceStatus = action == "stop" ? .stopped : .running
        for attempt in 0..<10 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return }
            await refresh()
            if services.first(where: { $0.id == serviceID })?.status == target { return }
        }
    }

    /// "Starting…", for a row or a menu while `action` is in flight.
    static func progressive(of action: String) -> String {
        switch action {
        case "start": return "Starting…"
        case "stop": return "Stopping…"
        default: return "Restarting…"
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
