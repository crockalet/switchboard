//
//  SwitchboardHUD.swift
//  Switchboard
//
//  Action feedback. Without this, a Restart in the menu bar is silent until the
//  next poll, and a refusal is only visible in the settings pane.
//

import DroppyKit
import SwiftUI

/// What the store asks the droplet to announce after an action settles.
public struct ActionAnnouncement: Sendable {
    public let symbol: String
    public let headline: String
    /// The refusal reason, when there is one. Present means the action failed.
    public let failure: String?

    public var isFailure: Bool { failure != nil }

    public init(symbol: String, headline: String, failure: String? = nil) {
        self.symbol = symbol
        self.headline = headline
        self.failure = failure
    }
}

/// A marker with no requirements: the runtime gates on the `hud` manifest
/// string, and the conformance is the statement of intent review reads.
extension SwitchboardDroplet: HUDPresenting {}

extension SwitchboardDroplet {
    /// Presents the result of a start, stop or restart.
    func announce(_ announcement: ActionAnnouncement) {
        guard let host else { return }

        // A failure is worth reading; a confirmation is not worth dwelling on.
        let duration: TimeInterval? = announcement.isFailure ? 4.0 : 2.0
        // `.high` is the band for things the user acted on directly, which is
        // exactly what this is: they pressed the button a moment ago.
        let priority = DropletHUDPriority.high
        let label = announcement.failure.map { "\(announcement.headline). \($0)" } ?? announcement.headline

        // Two shapes, not one shape with an empty half. A confirmation is a
        // strip and never grows: passing an `expanded:` closure for it would
        // give the host a card holding a title and a blank line.
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

        // Refused when the capability is missing or a higher band owns the
        // surface. Not worth surfacing to the user — the list still updates.
        if !host.hud.present(request) {
            host.log.info("Switchboard: HUD refused for \(announcement.headline)")
        }
    }

    /// Glyph at the far left, text at the far right, nothing in the middle: the
    /// host hands a strip the full width, and on a notch the middle of that
    /// width is the camera housing.
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
