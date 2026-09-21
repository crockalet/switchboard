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
                id: "switchboard",
                title: "Switchboard",
                systemImage: "dot.radiowaves.left.and.right",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 420,
                    preferredPairedWidth: 210,
                    // The height the rows actually need. `widgetDescriptors` is
                    // a computed property the host re-reads on a state-change
                    // broadcast, so this tracks the list instead of declaring a
                    // fixed card with dead space under a short one. Resizing a
                    // mounted widget would be shelf.invalidateLayout(for:),
                    // which costs the `shelf-write` capability; it is not worth
                    // one for this.
                    contentHeight: .fixed(Self.cardHeight(rows: store.services.count))
                )
            )
        ]
    }

    /// Header, then one 26pt row per service with 6pt between them, capped at
    /// the four rows the widget shows. The empty state needs room for two lines.
    static func cardHeight(rows: Int) -> CGFloat {
        let header: CGFloat = 20 + DroppySpacing.sm
        guard rows > 0 else { return header + 40 }
        let visible = CGFloat(min(rows, 4))
        return header + visible * 26 + (visible - 1) * DroppySpacing.xsm
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(SwitchboardWidget(droplet: self, store: store, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

/// Solo and paired are different compositions, not one view at two widths.
private struct SwitchboardWidget: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore
    let context: ShelfWidgetContext

    private var visibleServices: [Service] {
        Array(store.services.prefix(context.isPaired ? 3 : 4))
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
            // Paired is half the width and the title already fills it; the
            // count truncates to "1/..." rather than shortening.
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

            // Paired is half the width, so it drops the lifecycle controls —
            // but opening the thing is the one action worth keeping at any
            // size, and it is the reason most people look at this row.
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

        // Absent for a portless-only row: reading the route table proves the
        // service exists, not how to restart it.
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
