import DroppyKit
import SwiftUI

extension SwitchboardDroplet: MenuBarExtraProviding {
    public func makeMenuBarExtra() -> MenuBarExtraDescriptor? {
        MenuBarExtraDescriptor(
            title: "Switchboard",
            systemImage: "dot.radiowaves.left.and.right"
        ) { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(SwitchboardMenu(droplet: self, store: self.store))
        }
    }
}

/// The host draws this in a panel under the status item, not in an NSMenu, so
/// it is a view of rows with their own buttons: a SwiftUI `Menu` here renders
/// as a pop-up button that never opens.
///
/// The panel is measured once, when it is built, which can be before the first
/// refresh has filled the list. So its height never depends on the data: the
/// list reserves five rows and scrolls past them, and the status line is
/// always there.
private struct SwitchboardMenu: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore

    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 24
    private static let listHeight = CGFloat(visibleRows) * rowHeight
        + CGFloat(visibleRows - 1) * DroppySpacing.xs

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            Group {
                if store.services.isEmpty {
                    Text("No services")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: DroppySpacing.xs) {
                            ForEach(store.services) { service in
                                row(service)
                            }
                        }
                        .droppyFlatGlassControls()
                    }
                    .scrollIndicators(.automatic)
                }
            }
            .frame(height: Self.listHeight)

            Text(status)
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                .lineLimit(1)

            Divider()

            HStack(spacing: DroppySpacing.sm) {
                Button("Refresh") { droplet.refresh() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
                Spacer(minLength: 0)
                Button("Settings…") { droplet.openSettings() }
                    .buttonStyle(DroppyQuietButtonStyle(size: .small))
            }
        }
        .foregroundStyle(AdaptiveColors.primaryTextAuto)
        // The host's panel pays no inset of its own: without this the dots
        // and the trailing buttons sit on its rounded edge.
        .padding(.horizontal, DroppySpacing.md)
        .padding(.vertical, DroppySpacing.sm)
        .frame(minWidth: 300, alignment: .leading)
    }

    private func row(_ service: Service) -> some View {
        HStack(spacing: DroppySpacing.sm) {
            Circle()
                .fill(service.status == .running ? Color.green : AdaptiveColors.secondaryTextAuto.opacity(0.5))
                .frame(width: 6, height: 6)

            Text(service.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer(minLength: DroppySpacing.md)

            if let port = service.port {
                Text(String(port))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.secondaryTextAuto)
            }

            ServiceControls(
                service: service,
                pendingAction: store.pending[service.id],
                failure: store.failures[service.id],
                onOpen: { droplet.open($0) },
                onShowLog: { droplet.showLogs(for: service) },
                onAction: { store.perform($0, on: service) }
            )
        }
        .frame(height: Self.rowHeight)
        // A portless-only row has no lifecycle buttons; say why.
        .help(service.actions.isEmpty ? "Read only: not in the companion's config" : "")
    }

    private var status: String {
        if !store.companionReachable { return "Companion not running: read only" }
        if !store.proxyRunning { return "The portless proxy is not running" }
        return "\(store.runningCount) of \(store.services.count) running"
    }
}
