//
//  SwitchboardLogs.swift
//  Switchboard
//
//  The log takeover. This is the one surface that justifies a takeover rather
//  than a bigger list: a log needs the room, and it is the reason you opened
//  Switchboard rather than glanced at it.
//

import Combine
import DroppyKit
import SwiftUI

/// Tails one service's log, and only while something is watching.
///
/// The poll starts when the view appears and stops when it disappears or the
/// host takes the surface down. Nothing here runs in the background: a tail
/// that outlives its surface is the "work that does not stop" rejection, and it
/// would also be reading a file every second for nobody.
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

    /// Names the service to show. Does not start polling: the view does that
    /// when it appears, so a surface that is never shown never reads a file.
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
            path = result.path
            lines = result.lines
            failure = result.path == nil
                ? "No log path. A launchd job needs StandardOutPath in its plist."
                : nil
        } catch {
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
                // Reading takes longer than the shelf's own grace period, and
                // the surface carries its own Close, which is the condition the
                // SDK puts on asking for this.
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
        // A log wants every line it can get. The host clamps to maximumSize
        // rather than refusing, so asking for the ceiling is safe, and the
        // standard size — 93pt with an empty tail — is unreadable for this.
        // Height to the ceiling, width left at the standard: the shelf has a
        // width people recognise, and a takeover that stretches past it reads
        // as a different app rather than a Droppy surface.
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
        // Every way out lands here, including our own dismiss, so this is the
        // one place the tail has to stop.
        logTail.stop()
    }
}

private struct LogSurface: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var tail: LogTail

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header

            if let failure = tail.failure {
                message(failure)
            } else if tail.lines.isEmpty {
                message(tail.isLoading ? "Reading…" : "Nothing logged yet.")
            } else {
                lineList
            }
        }
        .padding(DroppySpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The whole point of the surface: read only while it is on screen.
        .onAppear { tail.start() }
        .onDisappear { tail.stop() }
    }

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 12, weight: .medium))
            Text(tail.serviceName)
                .font(.system(size: 12, weight: .semibold))
            if let path = tail.path {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Close") { droplet.dismissLogs() }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var lineList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tail.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
            }
            .onChange(of: tail.lines.count) { _, count in
                // A log is read at the bottom.
                guard count > 0 else { return }
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }
}
