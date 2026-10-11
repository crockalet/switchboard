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
    /// The endpoint requests go to, re-read from the companion's files on
    /// every refresh.
    @Published public private(set) var companionEndpoint = CompanionEndpoint()

    /// Set by the droplet, which owns how an announcement is shown.
    public var announce: ((ActionAnnouncement) -> Void)?
    /// Set by the droplet, so the log tail follows a new port or token.
    public var clientChanged: ((CompanionClient) -> Void)?

    public static let minimumRefreshInterval: TimeInterval = 5
    /// Between refreshes while nothing that shows the list is on screen.
    public static let idleRefreshInterval: TimeInterval = 60

    /// Seconds between refreshes while the list is on screen.
    public var refreshInterval: TimeInterval = 5 {
        didSet { if isWatched { restartLoop() } }
    }

    /// Whether the shelf widget, the menu bar panel or the settings pane is
    /// showing; the droplet keeps it current.
    public var isWatched = false {
        didSet {
            // Coming into view refreshes at once rather than after an idle wait.
            if isWatched, !oldValue { restartLoop() }
        }
    }

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
    private var lastDecodeFailure: String?
    private weak var log: (any DropletLogService)?

    public init(portless: PortlessSource = PortlessSource()) {
        self.portless = portless
        self.companion = CompanionClient()
    }

    private func resolveCompanion() {
        let endpoint = CompanionLocator.endpoint()
        guard endpoint != companion.endpoint else { return }
        companion = CompanionClient(endpoint: endpoint)
        companionEndpoint = endpoint
        clientChanged?(companion)
    }

    // MARK: - Lifecycle

    public func start(log: (any DropletLogService)? = nil) {
        self.log = log
        stop()
        isRunning = true
        clientChanged?(companion)
        restartLoop()
    }

    /// Restarts only the poller, leaving actions in flight alone. The first
    /// pass refreshes at once.
    private func restartLoop() {
        guard isRunning else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                let interval = self.isWatched
                    ? max(self.refreshInterval, Self.minimumRefreshInterval)
                    : Self.idleRefreshInterval
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
        lastDecodeFailure = nil
        isWatched = false
    }

    // MARK: - Refresh

    public func refresh() async {
        guard isRunning else { return }
        generation += 1
        let token = generation
        resolveCompanion()

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
        } catch CompanionError.unauthorized {
            reachable = false
            error = Self.tokenMismatch
        } catch let failure {
            // A poller restarted mid-request; the next pass answers.
            if Task.isCancelled { return }
            reachable = false
            error = "The companion sent a reply Switchboard cannot read."
            let detail = String(describing: failure)
            // Once per distinct failure, not once per poll.
            if detail != lastDecodeFailure {
                lastDecodeFailure = detail
                log?.error("Switchboard: unreadable companion reply — \(detail)")
            }
        }

        // Disabled, overtaken by a newer refresh or cancelled while this one waited.
        guard token == generation, isRunning, !Task.isCancelled else { return }
        if error == nil { lastDecodeFailure = nil }

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
                    headline: Self.headline(for: action, on: service.name, succeeded: true)
                ))
            } catch CompanionError.refused(let message) {
                guard let self, !Task.isCancelled else { return }
                self.showFailure(message, on: service.id)
                self.lastError = message
                self.log?.error("Switchboard: \(action) on \(id) refused — \(message)")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: Self.headline(for: action, on: service.name, succeeded: false),
                    failure: message
                ))
            } catch CompanionError.unauthorized {
                guard let self, !Task.isCancelled else { return }
                self.showFailure(Self.tokenMismatch, on: service.id)
                self.lastError = Self.tokenMismatch
                self.log?.error("Switchboard: \(action) on \(id) refused — token mismatch")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: Self.headline(for: action, on: service.name, succeeded: false),
                    failure: Self.tokenMismatch
                ))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.showFailure("The companion is not reachable.", on: service.id)
                self.lastError = "The companion is not reachable."
                self.log?.error("Switchboard: \(action) on \(id) failed — \(error)")
                self.announce?(ActionAnnouncement(
                    symbol: "exclamationmark.triangle.fill",
                    headline: Self.headline(for: action, on: service.name, succeeded: false),
                    failure: "The companion is not reachable."
                ))
            }
        }
    }

    private func showFailure(_ message: String, on serviceID: String) {
        failures[serviceID] = message
        failureTasks[serviceID]?.cancel()
        failureTasks[serviceID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
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

    /// A whole sentence per action and outcome, so each can be translated.
    static func headline(for action: String, on name: String, succeeded: Bool) -> String {
        switch (action, succeeded) {
        case ("start", true): return "\(name) started"
        case ("start", false): return "\(name) did not start"
        case ("stop", true): return "\(name) stopped"
        case ("stop", false): return "\(name) did not stop"
        case (_, true): return "\(name) restarted"
        case (_, false): return "\(name) did not restart"
        }
    }

    static let tokenMismatch = "The companion did not accept Switchboard's token. Restart switchboard-agent."

    public var runningCount: Int {
        services.filter { $0.status == .running }.count
    }
}
