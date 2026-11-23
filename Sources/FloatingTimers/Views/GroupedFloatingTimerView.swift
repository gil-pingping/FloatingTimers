import AppKit
import SwiftUI

private enum GroupedTimerHUDMetrics {
    static let expandedSide: CGFloat = 132
    static let minimizedWidth: CGFloat = 128
    static let minimizedHeight: CGFloat = 40
    static let clockDiameter: CGFloat = 112
    static let ringPadding: CGFloat = 7
    static let innerRingPadding: CGFloat = 13
    static let markerOrbitInset: CGFloat = 10
    static let markerSize: CGFloat = 6
    static let finishedMarkerSize: CGFloat = 9
}

private struct GroupCheckpointMarker: Identifiable {
    let id: UUID
    let progress: Double
    let isFinished: Bool
}

struct GroupedFloatingTimerView: View {
    @EnvironmentObject private var store: TimerStore

    let groupID: UUID

    @State private var isAlertPulsing = false
    @State private var isHovering = false

    static func preferredSize(memberCount _: Int, isMinimized: Bool) -> NSSize {
        if isMinimized {
            return NSSize(width: GroupedTimerHUDMetrics.minimizedWidth, height: GroupedTimerHUDMetrics.minimizedHeight)
        }

        return NSSize(width: GroupedTimerHUDMetrics.expandedSide, height: GroupedTimerHUDMetrics.expandedSide)
    }

    private var group: TimerGroup? {
        store.group(for: groupID)
    }

    private var timers: [TimerItem] {
        store.timers(inGroup: groupID)
    }

    private var isMinimized: Bool {
        store.minimizedGroupIDs.contains(groupID)
    }

    private var timelineDuration: TimeInterval {
        max(timers.map(\.initialDuration).max() ?? 1, 1)
    }

    private var displayedRemainingDuration: TimeInterval {
        max(timers.map(\.remainingDuration).max() ?? 0, 0)
    }

    private var displayedWholeSeconds: Int {
        max(Int(ceil(displayedRemainingDuration)), 0)
    }

    private var displayedProgress: Double {
        min(max((timelineDuration - displayedRemainingDuration) / timelineDuration, 0), 1)
    }

    private var displayedTimeText: String {
        DurationFormatter.clockString(totalSeconds: displayedWholeSeconds)
    }

    private var finishedCount: Int {
        timers.filter(\.isFinished).count
    }

    private var allFinished: Bool {
        !timers.isEmpty && finishedCount == timers.count
    }

    private var hasCheckpointCompletion: Bool {
        finishedCount > 0 && !allFinished
    }

    private var visualState: TimerState {
        if allFinished {
            return .finished
        }

        if timers.contains(where: { $0.state == .running }) {
            return .running
        }

        if timers.contains(where: { $0.state == .paused }) {
            return .paused
        }

        return .idle
    }

    private var checkpointMarkers: [GroupCheckpointMarker] {
        guard timers.count > 1 else {
            return []
        }

        let sortedTimers = timers.sorted { lhs, rhs in
            if lhs.initialDuration == rhs.initialDuration {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.initialDuration < rhs.initialDuration
        }

        var didSkipTimelineTimer = false
        let markerTimers = sortedTimers.filter { timer in
            let isTimelineTimer = abs(timer.initialDuration - timelineDuration) < 0.001
            if isTimelineTimer, !didSkipTimelineTimer {
                didSkipTimelineTimer = true
                return false
            }

            return true
        }

        let groupedTimers = Dictionary(grouping: markerTimers) { timer in
            Int(((timer.initialDuration / timelineDuration) * 10_000).rounded())
        }

        return groupedTimers.keys.sorted().flatMap { key in
            let samePointTimers = (groupedTimers[key] ?? []).sorted { $0.createdAt < $1.createdAt }

            return samePointTimers.enumerated().map { index, timer in
                let duplicateCount = samePointTimers.count
                let centeredIndex = Double(index) - Double(duplicateCount - 1) / 2
                let offset = duplicateCount > 1 ? centeredIndex * 0.018 : 0
                let rawProgress = (timer.initialDuration / timelineDuration) + offset
                let clampedProgress = min(max(rawProgress, 0.05), 0.95)

                return GroupCheckpointMarker(
                    id: timer.id,
                    progress: clampedProgress,
                    isFinished: timer.isFinished
                )
            }
        }
    }

    var body: some View {
        Group {
            if let group, !timers.isEmpty {
                content(for: group)
                    .contextMenu {
                        if isMinimized {
                            Button("복원") {
                                store.restoreGroupHUD(group.id)
                            }
                        } else {
                            Button("최소화") {
                                store.minimizeGroupHUD(group.id)
                            }
                        }

                        Divider()

                        Button("메인 UI 열기") {
                            NotificationCenter.default.post(name: .showMainWindow, object: nil)
                        }

                        Divider()

                        Button(primaryMenuTitle) {
                            primaryAction(for: group)
                        }

                        Button("그룹 멈춤") {
                            store.pauseGroup(group.id)
                        }

                        Button("그룹 초기화") {
                            store.resetGroup(group.id)
                        }

                        Button("그룹 재시작") {
                            store.restartGroup(group.id)
                        }

                        Divider()

                        Button("그룹 해제", role: .destructive) {
                            store.ungroup(group.id)
                        }
                    }
                    .onAppear {
                        updateAlertPulse(isActive: finishedCount > 0)
                    }
                    .onChange(of: finishedCount) { _, newValue in
                        updateAlertPulse(isActive: newValue > 0)
                    }
                    .onHover { isHovering = $0 }
                    .opacity(store.floatingOpacity)
            } else {
                Color.clear
                    .frame(
                        width: GroupedTimerHUDMetrics.expandedSide,
                        height: GroupedTimerHUDMetrics.expandedSide
                    )
            }
        }
    }

    @ViewBuilder
    private func content(for group: TimerGroup) -> some View {
        if isMinimized {
            minimizedBody
                .contentShape(Capsule())
                .onTapGesture {
                    store.restoreGroupHUD(group.id)
                }
                .frame(
                    width: GroupedTimerHUDMetrics.minimizedWidth,
                    height: GroupedTimerHUDMetrics.minimizedHeight
                )
        } else {
            expandedBody(for: group)
                .contentShape(Circle())
                .onTapGesture(count: 2) {
                    primaryAction(for: group)
                }
                .frame(
                    width: GroupedTimerHUDMetrics.expandedSide,
                    height: GroupedTimerHUDMetrics.expandedSide
                )
        }
    }

    private func expandedBody(for group: TimerGroup) -> some View {
        ZStack {
            ZStack {
                Color.clear

                if allFinished {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.red.opacity(isAlertPulsing ? 0.34 : 0.16),
                                    Color.red.opacity(0.05),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 10,
                                endRadius: 74
                            )
                        )
                        .frame(width: 120, height: 120)
                        .scaleEffect(isAlertPulsing ? 1.08 : 0.96)
                }

                clockBody
            }
            .frame(width: GroupedTimerHUDMetrics.expandedSide, height: GroupedTimerHUDMetrics.expandedSide)

            if isHovering {
                VStack {
                    HStack {
                        Spacer()

                        FloatingCornerButton(systemImage: "minus") {
                            store.minimizeGroupHUD(group.id)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 12)

                    Spacer()

                    FloatingBottomControls(
                        primaryAction: {
                            primaryAction(for: group)
                        },
                        resetAction: {
                            store.resetGroup(group.id)
                        },
                        primaryIcon: primaryActionIcon
                    )
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private var minimizedBody: some View {
        let theme = TimerColorTheme(state: visualState, hasAlert: hasCheckpointCompletion, isPulsing: isAlertPulsing)
        
        return ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
                .opacity(0.78)

            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.edgeColor.opacity(0.98),
                            theme.centerColor,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 8) {
                Circle()
                    .fill(theme.ringColor)
                    .frame(width: 6, height: 6)

                Text(displayedTimeText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text("\(timers.count)")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: theme.haloColor, radius: 6)
    }

    private var clockBody: some View {
        let theme = TimerColorTheme(state: visualState, hasAlert: hasCheckpointCompletion, isPulsing: isAlertPulsing)
        
        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.0001))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.centerColor,
                            theme.edgeColor,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 78
                    )
                )
                .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)

            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Circle())
                .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)
                .opacity(0.68)

            Circle()
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.9)
                .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)

            Circle()
                .trim(from: 0, to: max(displayedProgress, 0.015))
                .stroke(
                    theme.ringColor,
                    style: StrokeStyle(lineWidth: 4.6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)
                .padding(GroupedTimerHUDMetrics.ringPadding)

            Circle()
                .strokeBorder(
                    hasCheckpointCompletion ? Color.red.opacity(isAlertPulsing ? 0.24 : 0.10) : Color.white.opacity(0.06),
                    lineWidth: hasCheckpointCompletion ? 1.4 : 1
                )
                .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)
                .padding(GroupedTimerHUDMetrics.innerRingPadding)

            checkpointMarkerLayer

            if allFinished {
                Circle()
                    .stroke(
                        Color(red: 1.0, green: 0.20, blue: 0.16).opacity(isAlertPulsing ? 0.95 : 0.42),
                        style: StrokeStyle(lineWidth: isAlertPulsing ? 6.2 : 3.2)
                    )
                    .frame(width: GroupedTimerHUDMetrics.clockDiameter, height: GroupedTimerHUDMetrics.clockDiameter)
                    .scaleEffect(isAlertPulsing ? 1.06 : 0.98)
            }

            Text(displayedTimeText)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.45)
                .lineLimit(1)
                .foregroundStyle(allFinished ? Color(red: 1.0, green: 0.93, blue: 0.93) : Color.white.opacity(0.96))
                .shadow(
                    color: allFinished ? Color.red.opacity(isAlertPulsing ? 0.68 : 0.22) : .clear,
                    radius: allFinished ? 10 : 0
                )
                .padding(.horizontal, 12)
        }
        .frame(width: GroupedTimerHUDMetrics.expandedSide, height: GroupedTimerHUDMetrics.expandedSide)
        .shadow(color: theme.haloColor, radius: allFinished ? 14 : 7)
        .animation(.easeInOut(duration: 0.82), value: isAlertPulsing)
    }

    private var checkpointMarkerLayer: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = GroupedTimerHUDMetrics.clockDiameter / 2 - GroupedTimerHUDMetrics.markerOrbitInset
            let center = CGPoint(x: size / 2, y: size / 2)

            ForEach(checkpointMarkers) { marker in
                let angle = Angle.degrees((marker.progress * 360) - 90)
                let x = center.x + CGFloat(cos(angle.radians)) * radius
                let y = center.y + CGFloat(sin(angle.radians)) * radius
                let markerSize = marker.isFinished
                    ? GroupedTimerHUDMetrics.finishedMarkerSize
                    : GroupedTimerHUDMetrics.markerSize

                ZStack {
                    if marker.isFinished {
                        Circle()
                            .fill(Color.red.opacity(isAlertPulsing ? 0.26 : 0.12))
                            .frame(width: markerSize + 8, height: markerSize + 8)
                            .scaleEffect(isAlertPulsing ? 1.08 : 0.92)
                    }

                    Circle()
                        .fill(marker.isFinished ? Color(red: 1.0, green: 0.32, blue: 0.24) : Color.white.opacity(0.88))
                        .frame(width: markerSize, height: markerSize)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    marker.isFinished ? Color.white.opacity(0.72) : Color.black.opacity(0.12),
                                    lineWidth: 0.8
                                )
                        }
                }
                .position(x: x, y: y)
            }
        }
        .frame(width: GroupedTimerHUDMetrics.expandedSide, height: GroupedTimerHUDMetrics.expandedSide)
    }



    private var fontSize: CGFloat {
        displayedWholeSeconds >= 3600 ? 20 : 24
    }

    private var primaryActionIcon: String {
        if timers.allSatisfy({ $0.state == .running }) {
            return "pause.fill"
        }

        if !timers.isEmpty && timers.allSatisfy(\.isFinished) {
            return "arrow.clockwise"
        }

        return "play.fill"
    }

    private var primaryMenuTitle: String {
        if timers.allSatisfy({ $0.state == .running }) {
            return "그룹 정지"
        }

        if !timers.isEmpty && timers.allSatisfy(\.isFinished) {
            return "그룹 재시작"
        }

        return "그룹 시작"
    }

    private func primaryAction(for group: TimerGroup) {
        if timers.allSatisfy({ $0.state == .running }) {
            store.pauseGroup(group.id)
        } else if !timers.isEmpty && timers.allSatisfy(\.isFinished) {
            store.restartGroup(group.id)
        } else {
            store.startGroup(group.id)
        }
    }

    private func updateAlertPulse(isActive: Bool) {
        guard isActive else {
            isAlertPulsing = false
            return
        }

        isAlertPulsing = false
        withAnimation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true)) {
            isAlertPulsing = true
        }
    }
}
