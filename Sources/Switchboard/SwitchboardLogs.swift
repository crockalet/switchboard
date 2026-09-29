// A log needs room enough to justify a takeover, not a bigger list.

import Combine
import DroppyKit
import SwiftUI

/// Tails one service's log only while its surface is visible.
@MainActor
public final class LogTail: ObservableObject {
    @Published public private(set) var lines: [String] = []
    @Published public private(set) var path: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var failure: String?

    /// The service being tailed, without the `companion:` row prefix.
    public private(set) var serviceID: String?
    public private(set) var serviceName: String = ""

    private var task: Task<Void, Never>?
    private var client: CompanionClient

    public init(client: CompanionClient) {
        self.client = client
    }

    public func clientChanged(to client: CompanionClient) {
        self.client = client
    }

    /// Names the service to show; polling starts only when the view appears.
    public func prepare(for service: Service) {
        let id = service.id.hasPrefix("companion:")
            ? String(service.id.dropFirst("companion:".count))
            : service.id
        if id != serviceID {
            lines = []
            path = nil
            failure = nil
        }
        serviceID = id
        serviceName = service.name
    }

    public func start() {
        guard let serviceID else { return }
        stop()
        isLoading = lines.isEmpty
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pull(serviceID)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isLoading = false
    }

    private func pull(_ id: String) async {
        do {
            let result = try await client.logs(for: id, lines: 300)
            // Closed or disabled while the request was out.
            guard !Task.isCancelled else { return }
            path = result.path
            lines = result.lines
            failure = result.path == nil
                ? "No log path. A launchd job needs StandardOutPath in its plist."
                : nil
        } catch {
            guard !Task.isCancelled else { return }
            failure = "The companion is not reachable."
        }
        isLoading = false
    }
}

// MARK: - Surface

extension SwitchboardDroplet: ExpandedSurfaceHosting {
    public var expandedSurfaceProvider: (any ExpandedSurfaceProviding)? { self }
}

extension SwitchboardDroplet: ExpandedSurfaceProviding {
    public var expandedSurfaces: [ExpandedSurfaceDescriptor] {
        [
            ExpandedSurfaceDescriptor(
                id: "switchboard.logs",
                title: "Service log",
                systemImage: "text.alignleft",
                // Logs outlive the shelf's grace period and have their own Close.
                suppresses: .autoCollapse
            )
        ]
    }

    public func makeExpandedSurfaceView(_ id: ExpandedSurfaceID, context: ExpandedSurfaceContext) -> AnyView {
        guard id == "switchboard.logs" else { return AnyView(EmptyView()) }
        return AnyView(LogSurface(droplet: self, tail: logTail))
    }

    public func expandedSurfaceSize(_ id: ExpandedSurfaceID, fitting proposal: ExpandedSurfaceSizeProposal) -> CGSize? {
        guard id == "switchboard.logs" else { return nil }
        // The host clamps maximumSize; the standard height is unreadable, while
        // the standard width keeps the takeover recognisably Droppy.
        return CGSize(
            width: proposal.standardSize.width,
            height: proposal.maximumSize.height
        )
    }

    public func expandedSurfaceDidDismiss(
        _ id: ExpandedSurfaceID,
        presentation: ExpandedSurfacePresentation,
        reason: ExpandedSurfaceDismissalReason
    ) {
        // Every dismissal path lands here, including our own.
        logTail.stop()
    }
}
