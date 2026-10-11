//
//  WindowVisibility.swift
//  Switchboard
//

import AppKit
import SwiftUI

extension View {
    /// Reports whether this view is in a window that is on screen. The menu
    /// bar panel is built once and only ordered in and out, so `onAppear` and
    /// `onDisappear` say nothing about whether anyone can see it.
    func onWindowVisibilityChange(_ action: @escaping @MainActor (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(onChange: action))
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: ReaderView, coordinator: ()) {
        view.detach()
    }

    final class ReaderView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var observer: NSObjectProtocol?
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            if let window {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
        }

        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            report(false)
        }

        private func report(_ forced: Bool? = nil) {
            let visible = forced ?? (window?.occlusionState.contains(.visible) ?? false)
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible)
        }
    }
}
