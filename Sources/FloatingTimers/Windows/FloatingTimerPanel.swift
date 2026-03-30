import AppKit
import SwiftUI

final class FloatingTimerPanel: NSPanel, NSWindowDelegate {
    var onUserClose: (() -> Void)?
    var onDidBecomeKey: (() -> Void)?
    var onDidMove: ((CGPoint) -> Void)?
    private var suppressCloseCallback = false

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        configurePanel()
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    func closeSilently() {
        suppressCloseCallback = true
        close()
    }

    func windowWillClose(_ notification: Notification) {
        guard !suppressCloseCallback else {
            suppressCloseCallback = false
            return
        }

        onUserClose?()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onDidBecomeKey?()
    }

    func windowDidMove(_ notification: Notification) {
        onDidMove?(frame.origin)
    }

    private func configurePanel() {
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        level = .screenSaver
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        delegate = self

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}

final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}
