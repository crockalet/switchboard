// Immediate feedback instead of waiting for the next service poll.

import DroppyKit
import SwiftUI

/// What the store asks the droplet to announce after an action settles.
public struct ActionAnnouncement: Sendable {
    public let symbol: String
    public let headline: String
    /// The refusal reason, when the action failed.
    public let failure: String?

    public var isFailure: Bool { failure != nil }

    public init(symbol: String, headline: String, failure: String? = nil) {
        self.symbol = symbol
        self.headline = headline
        self.failure = failure
    }
}

/// The runtime gates on the `hud` manifest string; the conformance declares it.
extension SwitchboardDroplet: HUDPresenting {}

extension SwitchboardDroplet {
    /// Presents the result of a start, stop or restart.
    func announce(_ announcement: ActionAnnouncement) {
        guard let host else { return }

        let duration: TimeInterval? = announcement.isFailure ? 4.0 : 2.0
        let priority = DropletHUDPriority.high
        let label = announcement.failure.map { "\(announcement.headline). \($0)" } ?? announcement.headline

        // A confirmation is a strip; an empty expanded half would look broken.
        let request: DropletHUDRequest
        if let failure = announcement.failure {
            request = DropletHUDRequest(
                id: "switchboard.action",
                duration: duration,
                priority: priority,
                accessibilityLabel: label,
                isExpanded: true,
                expandedContentHeight: 64,
                content: { Self.strip(announcement) },
                expanded: {
                    VStack(alignment: .leading, spacing: DroppySpacing.xs) {
                        Text(announcement.headline)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        Text(failure)
                            .font(.system(size: 13))
                            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
        } else {
            request = DropletHUDRequest(
                id: "switchboard.action",
                duration: duration,
                priority: priority,
                accessibilityLabel: label,
                content: { Self.strip(announcement) }
            )
        }

        if host.hud.present(request) { return }
        // The card can be refused where a strip is not; the headline alone
        // still says what failed, and the row carries the reason.
        if announcement.isFailure, host.hud.present(DropletHUDRequest(
            id: "switchboard.action",
            duration: duration,
            priority: priority,
            accessibilityLabel: label,
            content: { Self.strip(announcement) }
        )) { return }
        host.log.info("Switchboard: HUD refused for \(announcement.headline)")
    }

    /// Keep the middle empty: on a notch it is the camera housing.
    @ViewBuilder
    static func strip(_ announcement: ActionAnnouncement) -> some View {
        HStack(spacing: 0) {
            Image(systemName: announcement.symbol)
                .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
            Spacer(minLength: 0)
            Text(announcement.headline)
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
    }
}
