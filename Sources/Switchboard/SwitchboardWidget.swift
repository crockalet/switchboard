//
//  SwitchboardWidget.swift
//  Switchboard
//

import DroppyKit
import SwiftUI

extension SwitchboardDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Switchboard",
                systemImage: "dot.radiowaves.left.and.right",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 420,
                    preferredPairedWidth: 210,
                    // Follows the list; activate(host:) invalidates the host's
                    // cached layout whenever this number changes.
                    contentHeight: .fixed(widgetHeight)
                )
            )
        ]
    }

    static let widgetID: ShelfWidgetID = "switchboard"

    /// Header plus up to four 26pt rows, with room for the empty state. The
    /// height is the whole rectangle, so it budgets the 16pt `contentInsets`
    /// takes under the 18pt card corner; a solo island card leaves it unused.
    static func cardHeight(rows: Int) -> CGFloat {
        let insets = 2 * DroppySpacing.sm
        let header: CGFloat = 20 + DroppySpacing.sm
        guard rows > 0 else { return insets + header + 40 }
        let visible = CGFloat(min(rows, 4))
        return insets + header + visible * 26 + (visible - 1) * DroppySpacing.xsm
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(SwitchboardWidget(droplet: self, store: store, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

/// Paired is a distinct composition, not the solo view at half width.
private struct SwitchboardWidget: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore
    let context: ShelfWidgetContext

    /// Four in both compositions: the declared height is one number for solo
    /// and grouped, so a shorter grouped list would leave an empty band.
    private var visibleServices: [Service] {
        Array(store.services.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            header

            if store.services.isEmpty {
                empty
            } else {
                VStack(spacing: DroppySpacing.xsm) {
                    ForEach(visibleServices) { service in
                        ServiceRow(
                            service: service,
                            isPaired: context.isPaired,
                            onOpen: { droplet.open($0) },
                            onAction: { store.perform($0, on: service) }
                        )
                    }
                }
                .droppyFlatGlassControls()
            }

            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 12, weight: .medium))
            Text("Switchboard")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            // Paired is too narrow for the count without awkward truncation.
            if !store.services.isEmpty, !context.isPaired {
                Text("\(store.runningCount)/\(store.services.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            if !context.isPaired {
                Button {
                    droplet.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Refresh")
                .accessibilityLabel("Refresh")
            }
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
            Text("No services")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            Text(store.proxyRunning
                 ? "Nothing is registered with portless yet."
                 : "The portless proxy is not running.")
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        }
    }
}

/// One service. Leading name, trailing state, controls only when something can
/// actually act on them.
private struct ServiceRow: View {
    let service: Service
    let isPaired: Bool
    let onOpen: (URL) -> Void
    let onAction: (String) -> Void

    var body: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Circle()
                .fill(service.status == .running
                      ? Color.green
                      : AdaptiveColors.notchSurfaceTertiaryText)
                .frame(width: 6, height: 6)

            Text(service.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            if !isPaired, let port = service.port {
                Text(String(port))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }

            // Paired drops lifecycle controls, but opening stays useful.
            if isPaired {
                openButton
            } else {
                controls
            }
        }
        .frame(height: 26)
    }

    @ViewBuilder
    private var openButton: some View {
        if let url = service.url {
            Button {
                onOpen(url)
            } label: {
                Image(systemName: "arrow.up.forward")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help("Open \(url.absoluteString)")
            .accessibilityLabel("Open \(service.name)")
        }
    }

    @ViewBuilder
    private var controls: some View {
        openButton

        // Absent for a portless-only row: only the companion can restart it.
        if service.actions.contains(.restart), service.status == .running {
            Button {
                onAction("restart")
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help("Restart \(service.name)")
            .accessibilityLabel("Restart \(service.name)")
        }

        if service.status == .running, service.actions.contains(.stop) {
            Button {
                onAction("stop")
            } label: {
                Image(systemName: "stop.fill")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help("Stop \(service.name)")
            .accessibilityLabel("Stop \(service.name)")
        } else if service.status != .running, service.actions.contains(.start) {
            Button {
                onAction("start")
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20))
            .help("Start \(service.name)")
            .accessibilityLabel("Start \(service.name)")
        }
    }
}
