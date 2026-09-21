//
//  LogSurfaceView.swift
//  Switchboard
//

import DroppyKit
import SwiftUI

struct LogSurface: View {
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
                guard count > 0 else { return }
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }
}
