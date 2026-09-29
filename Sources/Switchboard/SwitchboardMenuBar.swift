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
private struct SwitchboardMenu: View {
    @ObservedObject var droplet: SwitchboardDroplet
    @ObservedObject var store: SwitchboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            if store.services.isEmpty {
                Text("No services")
                    .font(.system(size: 13, weight: .medium))
            } else {
                VStack(spacing: DroppySpacing.xs) {
                    ForEach(store.services) { service in
                        row(service)
                    }
                }
                .droppyFlatGlassControls()
            }

            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.secondaryTextAuto)
            }

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
        .padding(.vertical, DroppySpacing.xs)
        .frame(minWidth: 280, alignment: .leading)
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
                onOpen: { droplet.open($0) },
                onShowLog: { droplet.showLogs(for: service) },
                onAction: { store.perform($0, on: service) }
            )
        }
        .frame(height: 24)
        // A portless-only row has no lifecycle buttons; say why.
        .help(service.actions.isEmpty ? "Read only: not in the companion's config" : "")
    }

    private var note: String? {
        if !store.companionReachable { return "Companion not running: read only" }
        if !store.proxyRunning { return "The portless proxy is not running" }
        return nil
    }
}
