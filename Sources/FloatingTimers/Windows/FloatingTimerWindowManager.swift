import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingTimerWindowManager {
    private weak var store: TimerStore?
    private var cancellable: AnyCancellable?
    private var timerPanels: [UUID: FloatingTimerPanel] = [:]
    private var groupPanels: [UUID: FloatingTimerPanel] = [:]
    private var memoPanels: [UUID: FloatingTimerPanel] = [:]
    private var controlPanel: FloatingTimerPanel?
    private var reopenObserver: NSObjectProtocol?
    private var memoFocusObserver: NSObjectProtocol?
    private var activeSpaceObserver: NSObjectProtocol?
    private var frontmostAppObserver: NSObjectProtocol?

    func bind(to store: TimerStore) {
        self.store = store
        ensureControlPanel()

        if reopenObserver == nil {
            reopenObserver = NotificationCenter.default.addObserver(
                forName: .showFloatingControlsPanel,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.store?.setControlPanelMode(.expanded)
                    self?.showControlPanel()
                }
            }
        }

        if memoFocusObserver == nil {
            memoFocusObserver = NotificationCenter.default.addObserver(
                forName: .focusFloatingMemoPanel,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let memoID = notification.object as? UUID else {
                    return
                }

                Task { @MainActor [weak self] in
                    self?.showMemoPanel(id: memoID)
                }
            }
        }

        if activeSpaceObserver == nil {
            activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshVisiblePanelsForActiveSpace()
                }
            }
        }

        if frontmostAppObserver == nil {
            frontmostAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshVisiblePanelsForActiveSpace()
                }
            }
        }

        cancellable = Publishers.CombineLatest(
            Publishers.CombineLatest4(
                store.$timers,
                store.$groups,
                store.$memos,
                store.$areFloatingHUDsVisible
            ),
            Publishers.CombineLatest4(
                store.$isFloatingCaptureExcluded,
                store.$controlPanelMode,
                store.$minimizedTimerIDs,
                store.$minimizedGroupIDs
            )
        )
        .combineLatest(store.$minimizedMemoIDs)
            .receive(on: RunLoop.main)
            .sink { [weak self] combinedState, minimizedMemoIDs in
                let (primaryState, secondaryState) = combinedState
                let (timers, groups, memos, areFloatingHUDsVisible) = primaryState
                let (isFloatingCaptureExcluded, controlPanelMode, minimizedTimerIDs, minimizedGroupIDs) = secondaryState

                self?.reconcile(
                    timers: timers,
                    groups: groups,
                    memos: memos,
                    areFloatingHUDsVisible: areFloatingHUDsVisible,
                    isFloatingCaptureExcluded: isFloatingCaptureExcluded,
                    controlPanelMode: controlPanelMode,
                    minimizedTimerIDs: minimizedTimerIDs,
                    minimizedGroupIDs: minimizedGroupIDs,
                    minimizedMemoIDs: minimizedMemoIDs
                )
            }
    }

    private func reconcile(
        timers: [TimerItem],
        groups: [TimerGroup],
        memos: [MemoItem],
        areFloatingHUDsVisible: Bool,
        isFloatingCaptureExcluded: Bool,
        controlPanelMode: FloatingPanelMode,
        minimizedTimerIDs: Set<UUID>,
        minimizedGroupIDs: Set<UUID>,
        minimizedMemoIDs: Set<UUID>
    ) {
        let groupedTimerIDs = Set(groups.flatMap(\.timerIDs))
        let activeTimerIDs = Set(timers.map(\.id).filter { !groupedTimerIDs.contains($0) })
        let activeGroupIDs = Set(groups.map(\.id))
        let activeMemoIDs = Set(memos.map(\.id))

        for (id, panel) in timerPanels where !activeTimerIDs.contains(id) {
            panel.closeSilently()
            timerPanels.removeValue(forKey: id)
        }

        for (id, panel) in groupPanels where !activeGroupIDs.contains(id) {
            panel.closeSilently()
            groupPanels.removeValue(forKey: id)
        }

        for (id, panel) in memoPanels where !activeMemoIDs.contains(id) {
            panel.closeSilently()
            memoPanels.removeValue(forKey: id)
        }

        for timer in timers where activeTimerIDs.contains(timer.id) && timerPanels[timer.id] == nil {
            let panel = makePanel(for: timer.id, isMinimized: minimizedTimerIDs.contains(timer.id))
            timerPanels[timer.id] = panel
        }

        for group in groups {
            if let panel = groupPanels[group.id] {
                updateGroupPanel(
                    panel,
                    groupID: group.id,
                    memberCount: group.timerIDs.count,
                    isMinimized: minimizedGroupIDs.contains(group.id)
                )
            } else {
                let panel = makeGroupPanel(
                    for: group.id,
                    memberCount: group.timerIDs.count,
                    isMinimized: minimizedGroupIDs.contains(group.id)
                )
                groupPanels[group.id] = panel
            }
        }

        for memo in memos where memoPanels[memo.id] == nil {
            let panel = makeMemoPanel(for: memo, isMinimized: minimizedMemoIDs.contains(memo.id))
            memoPanels[memo.id] = panel
        }

        for timer in timers where activeTimerIDs.contains(timer.id) {
            guard let panel = timerPanels[timer.id] else {
                continue
            }

            updateTimerPanel(panel, timerID: timer.id, isMinimized: minimizedTimerIDs.contains(timer.id))
            applyCaptureSharing(to: panel, isExcluded: isFloatingCaptureExcluded)
            setPanel(panel, visible: areFloatingHUDsVisible)
        }

        for group in groups {
            guard let panel = groupPanels[group.id] else {
                continue
            }

            updateGroupPanel(
                panel,
                groupID: group.id,
                memberCount: group.timerIDs.count,
                isMinimized: minimizedGroupIDs.contains(group.id)
            )
            applyCaptureSharing(to: panel, isExcluded: isFloatingCaptureExcluded)
            setPanel(panel, visible: areFloatingHUDsVisible)
        }

        for memo in memos {
            guard let panel = memoPanels[memo.id] else {
                continue
            }

            updateMemoPanel(panel, memo: memo, isMinimized: minimizedMemoIDs.contains(memo.id))
            applyCaptureSharing(to: panel, isExcluded: isFloatingCaptureExcluded)
            setPanel(panel, visible: areFloatingHUDsVisible)
        }

        if controlPanelMode.isVisible {
            ensureControlPanel()
            updateControlPanel(mode: controlPanelMode)
            if let controlPanel {
                applyCaptureSharing(to: controlPanel, isExcluded: isFloatingCaptureExcluded)
                setPanel(controlPanel, visible: true)
            }
        } else {
            controlPanel?.orderOut(nil)
        }
    }

    private func makePanel(for id: UUID, isMinimized: Bool) -> FloatingTimerPanel {
        let size = FloatingTimerView.preferredSize(isMinimized: isMinimized)
        let frame = restoredFrame(
            size: size,
            storedOrigin: store?.timerPanelOrigin(for: id),
            fallback: nextPanelFrame(size: size)
        )
        let panel = FloatingTimerPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        applyPanelSize(size, to: panel)
        applyCaptureSharing(to: panel, isExcluded: store?.isFloatingCaptureExcluded ?? false)

        if let store {
            panel.contentView = MovableHostingView(
                rootView: FloatingTimerView(timerID: id)
                    .environmentObject(store)
            )
        }

        panel.onUserClose = { [weak self, weak store] in
            store?.removeTimer(id)
            self?.timerPanels.removeValue(forKey: id)
        }
        panel.onDidMove = { [weak store] origin in
            store?.setTimerPanelOrigin(id, origin: origin)
        }
        store?.setTimerPanelOrigin(id, origin: panel.frame.origin)

        return panel
    }

    private func updateTimerPanel(_ panel: FloatingTimerPanel, timerID: UUID, isMinimized: Bool) {
        applyPanelSize(FloatingTimerView.preferredSize(isMinimized: isMinimized), to: panel)
        store?.setTimerPanelOrigin(timerID, origin: panel.frame.origin)
    }

    private func nextPanelFrame(size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offsetIndex = timerPanels.count
        let columnOffset = CGFloat(offsetIndex % 6) * 18
        let rowOffset = CGFloat(offsetIndex % 7) * 20
        let x = max(visibleFrame.minX + 24, visibleFrame.maxX - size.width - 28 - columnOffset)
        let y = max(visibleFrame.minY + 24, visibleFrame.maxY - size.height - 74 - rowOffset)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func makeGroupPanel(for id: UUID, memberCount: Int, isMinimized: Bool) -> FloatingTimerPanel {
        let size = GroupedFloatingTimerView.preferredSize(memberCount: memberCount, isMinimized: isMinimized)
        let panel = FloatingTimerPanel(
            contentRect: restoredFrame(
                size: size,
                storedOrigin: store?.groupPanelOrigin(for: id),
                fallback: nextGroupPanelFrame(size: size)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        applyPanelSize(size, to: panel)
        applyCaptureSharing(to: panel, isExcluded: store?.isFloatingCaptureExcluded ?? false)

        if let store {
            panel.contentView = MovableHostingView(
                rootView: GroupedFloatingTimerView(groupID: id)
                    .environmentObject(store)
            )
        }

        panel.onUserClose = { [weak self, weak store] in
            store?.ungroup(id)
            self?.groupPanels.removeValue(forKey: id)
        }
        panel.onDidMove = { [weak store] origin in
            store?.setGroupPanelOrigin(id, origin: origin)
        }
        store?.setGroupPanelOrigin(id, origin: panel.frame.origin)

        return panel
    }

    private func updateGroupPanel(_ panel: FloatingTimerPanel, groupID: UUID, memberCount: Int, isMinimized: Bool) {
        applyPanelSize(
            GroupedFloatingTimerView.preferredSize(memberCount: memberCount, isMinimized: isMinimized),
            to: panel
        )
        store?.setGroupPanelOrigin(groupID, origin: panel.frame.origin)
    }

    private func nextGroupPanelFrame(size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offsetIndex = groupPanels.count
        let x = max(visibleFrame.minX + 24, visibleFrame.maxX - size.width - 30)
        let y = min(
            visibleFrame.maxY - size.height - 126,
            visibleFrame.minY + 166 + CGFloat(offsetIndex) * 20
        )

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func makeMemoPanel(for memo: MemoItem, isMinimized: Bool) -> FloatingTimerPanel {
        let size = FloatingMemoView.preferredSize(for: memo, isMinimized: isMinimized)
        let panel = FloatingTimerPanel(
            contentRect: restoredFrame(
                size: size,
                storedOrigin: store?.memoPanelOrigin(for: memo.id),
                fallback: nextMemoPanelFrame(size: size)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        applyPanelSize(size, to: panel)
        applyCaptureSharing(to: panel, isExcluded: store?.isFloatingCaptureExcluded ?? true)

        if let store {
            panel.contentView = MovableHostingView(
                rootView: FloatingMemoView(memoID: memo.id)
                    .environmentObject(store)
            )
        }

        panel.onUserClose = { [weak self, weak store] in
            store?.removeMemo(memo.id)
            self?.memoPanels.removeValue(forKey: memo.id)
        }
        panel.onDidBecomeKey = { [weak store] in
            store?.markMemoFocused(memo.id)
        }
        panel.onDidMove = { [weak store] origin in
            store?.setMemoPanelOrigin(memo.id, origin: origin)
        }
        store?.setMemoPanelOrigin(memo.id, origin: panel.frame.origin)

        return panel
    }

    private func updateMemoPanel(_ panel: FloatingTimerPanel, memo: MemoItem, isMinimized: Bool) {
        applyMemoPanelSize(FloatingMemoView.preferredSize(for: memo, isMinimized: isMinimized), to: panel)
        store?.setMemoPanelOrigin(memo.id, origin: panel.frame.origin)
    }

    private func nextMemoPanelFrame(size: NSSize) -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offsetIndex = memoPanels.count
        let columnOffset = CGFloat(offsetIndex % 5) * 24
        let rowOffset = CGFloat(offsetIndex % 6) * 20
        let x = min(visibleFrame.maxX - size.width - 24, visibleFrame.minX + 34 + columnOffset)
        let y = max(visibleFrame.minY + 34, visibleFrame.maxY - size.height - 90 - rowOffset)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func ensureControlPanel() {
        guard controlPanel == nil else {
            return
        }

        guard let store else {
            return
        }

        let panel = FloatingTimerPanel(
            contentRect: restoredFrame(
                size: FloatingControlPanelView.preferredSize(for: .expanded),
                storedOrigin: store.controlPanelOrigin,
                fallback: nextControlPanelFrame()
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        applyPanelSize(FloatingControlPanelView.preferredSize(for: .expanded), to: panel)
        applyCaptureSharing(to: panel, isExcluded: store.isFloatingCaptureExcluded)
        panel.contentView = MovableHostingView(
            rootView: FloatingControlPanelView()
                .environmentObject(store)
        )
        panel.onUserClose = { [weak store] in
            store?.setControlPanelMode(.hidden)
        }
        panel.onDidMove = { [weak store] origin in
            store?.setControlPanelOrigin(origin)
        }
        store.setControlPanelOrigin(panel.frame.origin)
        controlPanel = panel
    }

    private func updateControlPanel(mode: FloatingPanelMode) {
        guard let controlPanel else {
            return
        }

        applyPanelSize(FloatingControlPanelView.preferredSize(for: mode), to: controlPanel)
        store?.setControlPanelOrigin(controlPanel.frame.origin)
    }

    private func showControlPanel() {
        if controlPanel == nil {
            ensureControlPanel()
        }

        if let controlPanel {
            applyPanelSize(FloatingControlPanelView.preferredSize(for: .expanded), to: controlPanel)
            store?.setControlPanelOrigin(controlPanel.frame.origin)
            if !controlPanel.isVisible {
                controlPanel.orderFrontRegardless()
            } else {
                controlPanel.makeKeyAndOrderFront(nil)
            }
        }
    }

    private func showMemoPanel(id: UUID) {
        guard let panel = memoPanels[id] else {
            return
        }

        if !panel.isVisible {
            panel.orderFrontRegardless()
        }

        panel.makeKeyAndOrderFront(nil)
    }

    private func restoredFrame(size: NSSize, storedOrigin: CGPoint?, fallback: NSRect) -> NSRect {
        guard let storedOrigin else {
            return clampFrame(fallback, size: size)
        }

        return clampFrame(NSRect(origin: storedOrigin, size: size), size: size)
    }

    private func refreshVisiblePanelsForActiveSpace() {
        let visiblePanels = allPanels.filter(\.isVisible)
        guard !visiblePanels.isEmpty else {
            return
        }

        refront(panels: visiblePanels)

        // Full-screen transitions animate across spaces, so reinforce the order a few
        // frames later to keep HUD panels attached to the newly active space.
        let retryDelays: [TimeInterval] = [0.18, 0.42]
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else {
                    return
                }

                self.refront(panels: self.allPanels.filter(\.isVisible))
            }
        }
    }

    private func refront(panels: [FloatingTimerPanel]) {
        for panel in panels {
            panel.orderFrontRegardless()
        }
    }

    private var allPanels: [FloatingTimerPanel] {
        var panels = Array(timerPanels.values)
        panels.append(contentsOf: groupPanels.values)
        panels.append(contentsOf: memoPanels.values)
        if let controlPanel {
            panels.append(controlPanel)
        }
        return panels
    }

    private func nextControlPanelFrame() -> NSRect {
        let size = FloatingControlPanelView.preferredSize(for: .expanded)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = max(visibleFrame.minX + 24, visibleFrame.maxX - size.width - 26)
        let y = max(visibleFrame.minY + 22, visibleFrame.minY + 28)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func setPanel(_ panel: FloatingTimerPanel, visible: Bool) {
        if visible {
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        } else {
            panel.orderOut(nil)
        }
    }

    private func applyPanelSize(_ size: NSSize, to panel: FloatingTimerPanel) {
        guard panel.frame.size != size else {
            panel.setContentSize(size)
            panel.minSize = size
            panel.maxSize = size
            return
        }

        let anchoredFrame = anchoredFrame(for: panel.frame, resizedTo: size)
        panel.setFrame(anchoredFrame, display: true)
        panel.minSize = size
        panel.maxSize = size
        panel.setContentSize(size)
    }

    private func applyMemoPanelSize(_ size: NSSize, to panel: FloatingTimerPanel) {
        guard panel.frame.size != size else {
            panel.setContentSize(size)
            panel.minSize = size
            panel.maxSize = size
            return
        }

        let anchoredFrame = topLeadingAnchoredFrame(for: panel.frame, resizedTo: size)
        panel.setFrame(anchoredFrame, display: true)
        panel.minSize = size
        panel.maxSize = size
        panel.setContentSize(size)
    }

    private func applyCaptureSharing(to panel: NSWindow, isExcluded: Bool) {
        panel.sharingType = isExcluded ? .none : .readOnly
    }

    private func anchoredFrame(for currentFrame: NSRect, resizedTo size: NSSize) -> NSRect {
        let maxX = currentFrame.maxX
        let maxY = currentFrame.maxY
        var frame = NSRect(x: maxX - size.width, y: maxY - size.height, width: size.width, height: size.height)

        if let visibleFrame = NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        }

        return frame
    }

    private func topLeadingAnchoredFrame(for currentFrame: NSRect, resizedTo size: NSSize) -> NSRect {
        let minX = currentFrame.minX
        let maxY = currentFrame.maxY
        var frame = NSRect(x: minX, y: maxY - size.height, width: size.width, height: size.height)

        if let visibleFrame = NSScreen.main?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        }

        return frame
    }

    private func clampFrame(_ frame: NSRect, size: NSSize) -> NSRect {
        var clampedFrame = NSRect(origin: frame.origin, size: size)

        if let visibleFrame = NSScreen.main?.visibleFrame {
            clampedFrame.origin.x = min(
                max(clampedFrame.origin.x, visibleFrame.minX + 12),
                visibleFrame.maxX - size.width - 12
            )
            clampedFrame.origin.y = min(
                max(clampedFrame.origin.y, visibleFrame.minY + 12),
                visibleFrame.maxY - size.height - 12
            )
        }

        return clampedFrame
    }
}

extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let showFloatingControlsPanel = Notification.Name("showFloatingControlsPanel")
    static let focusFloatingMemoPanel = Notification.Name("focusFloatingMemoPanel")
}
