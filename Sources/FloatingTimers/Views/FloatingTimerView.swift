import SwiftUI

struct FloatingTimerView: View {
    @EnvironmentObject private var store: TimerStore

    let timerID: UUID

    @State private var isPulsing = false
    @State private var isHovering = false

    static func preferredSize(isMinimized: Bool) -> CGSize {
        isMinimized ? CGSize(width: 118, height: 40) : CGSize(width: 136, height: 136)
    }

    private var timer: TimerItem? {
        store.timer(for: timerID)
    }

    private var isMinimized: Bool {
        store.minimizedTimerIDs.contains(timerID)
    }

    var body: some View {
        Group {
            if let timer {
                content(for: timer)
                    .contextMenu {
                        if isMinimized {
                            Button("복원") {
                                store.restoreTimerHUD(timer.id)
                            }
                        } else {
                            Button("최소화") {
                                store.minimizeTimerHUD(timer.id)
                            }
                        }

                        Divider()

                        Button("메인 UI 열기") {
                            NotificationCenter.default.post(name: .showMainWindow, object: nil)
                        }

                        Divider()

                        Button(primaryActionLabel(for: timer)) {
                            primaryAction(for: timer)
                        }

                        Button("초기화") {
                            store.reset(timer.id)
                        }

                        Button("재시작") {
                            store.restart(timer.id)
                        }

                        Divider()

                        Button("삭제", role: .destructive) {
                            store.removeTimer(timer.id)
                        }
                    }
                    .onAppear {
                        updatePulse(for: timer.state)
                    }
                    .onChange(of: timer.state) { _, newValue in
                        updatePulse(for: newValue)
                    }
                    .onHover { isHovering = $0 }
                    .opacity(store.floatingOpacity)
            } else {
                Color.clear
                    .frame(
                        width: Self.preferredSize(isMinimized: false).width,
                        height: Self.preferredSize(isMinimized: false).height
                    )
            }
        }
    }

    @ViewBuilder
    private func content(for timer: TimerItem) -> some View {
        if isMinimized {
            minimizedBody(timer)
                .contentShape(Capsule())
                .onTapGesture {
                    store.restoreTimerHUD(timer.id)
                }
                .frame(
                    width: Self.preferredSize(isMinimized: true).width,
                    height: Self.preferredSize(isMinimized: true).height
                )
        } else {
            expandedBody(timer)
                .contentShape(Circle())
                .onTapGesture(count: 2) {
                    primaryAction(for: timer)
                }
                .frame(
                    width: Self.preferredSize(isMinimized: false).width,
                    height: Self.preferredSize(isMinimized: false).height
                )
        }
    }

    private func expandedBody(_ timer: TimerItem) -> some View {
        let theme = TimerColorTheme(state: timer.state, hasAlert: false, isPulsing: isPulsing)
        
        return ZStack {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.0001))

                if timer.isFinished {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.15, blue: 0.12).opacity(isPulsing ? 0.40 : 0.20),
                                    Color.red.opacity(0.04),
                                    Color.clear,
                                ],
                                center: .center,
                                startRadius: 6,
                                endRadius: 66
                            )
                        )
                        .scaleEffect(isPulsing ? 1.12 : 0.92)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.centerColor,
                                theme.edgeColor,
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: 86
                        )
                    )

                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(Circle())
                    .opacity(0.70)

                Circle()
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.9)

                Circle()
                    .trim(from: 0, to: max(timer.progress, 0.015))
                    .stroke(
                        theme.ringColor,
                        style: StrokeStyle(lineWidth: 4.8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(7)

                Circle()
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    .padding(13)

                if timer.isFinished {
                    Circle()
                        .stroke(
                            Color(red: 1.0, green: 0.20, blue: 0.16).opacity(isPulsing ? 0.95 : 0.42),
                            style: StrokeStyle(lineWidth: isPulsing ? 6.5 : 3.2)
                        )
                        .scaleEffect(isPulsing ? 1.10 : 0.96)
                }

                Text(timer.remainingDurationText)
                    .font(.system(size: fontSize(for: timer), weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(timer.isFinished ? Color(red: 1.0, green: 0.93, blue: 0.93) : Color.white.opacity(0.96))
                    .shadow(color: timer.isFinished ? Color.red.opacity(isPulsing ? 0.68 : 0.24) : .clear, radius: timer.isFinished ? 10 : 0)
                    .padding(.horizontal, 14)
            }
            .shadow(color: theme.haloColor, radius: timer.isFinished ? 14 : 7)
            .scaleEffect(timer.isFinished ? (isPulsing ? 1.01 : 0.99) : 1)
            .opacity(timer.isFinished ? (isPulsing ? 1 : 0.95) : 1)
            .padding(4)
            .animation(.easeInOut(duration: 0.85), value: isPulsing)

            if isHovering {
                VStack {
                    HStack {
                        Spacer()

                        FloatingCornerButton(systemImage: "minus") {
                            store.minimizeTimerHUD(timer.id)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 12)

                    Spacer()

                    FloatingBottomControls(
                        primaryAction: {
                            primaryAction(for: timer)
                        },
                        resetAction: {
                            store.reset(timer.id)
                        },
                        primaryIcon: primaryActionIcon(for: timer)
                    )
                    .padding(.bottom, 10)
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    private func minimizedBody(_ timer: TimerItem) -> some View {
        let theme = TimerColorTheme(state: timer.state, hasAlert: false, isPulsing: isPulsing)
        
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
                    .frame(width: timer.isFinished ? 8 : 6, height: timer.isFinished ? 8 : 6)
                    .shadow(color: theme.ringColor.opacity(0.42), radius: 4)

                Text(timer.remainingDurationText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
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

    private func fontSize(for timer: TimerItem) -> CGFloat {
        timer.remainingWholeSeconds >= 3600 ? 20 : 26
    }

    private func primaryActionIcon(for timer: TimerItem) -> String {
        switch timer.state {
        case .running:
            return "pause.fill"
        case .finished:
            return "arrow.clockwise"
        case .idle, .paused:
            return "play.fill"
        }
    }

    private func primaryActionLabel(for timer: TimerItem) -> String {
        switch timer.state {
        case .running:
            return "멈춤"
        case .finished:
            return "다시 시작"
        case .idle, .paused:
            return "시작"
        }
    }

    private func primaryAction(for timer: TimerItem) {
        switch timer.state {
        case .running:
            store.pause(timer.id)
        case .finished:
            store.restart(timer.id)
        case .idle, .paused:
            store.start(timer.id)
        }
    }

    private func updatePulse(for state: TimerState) {
        guard state == .finished else {
            isPulsing = false
            return
        }

        isPulsing = false
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

struct FloatingBottomControls: View {
    let primaryAction: () -> Void
    let resetAction: () -> Void
    let primaryIcon: String

    var body: some View {
        HStack(spacing: 6) {
            Button(action: primaryAction) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 11, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button(action: resetAction) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.26))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct FloatingCornerButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "\(systemImage).circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.86), Color.black.opacity(0.38))
        }
        .buttonStyle(.plain)
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
    }
}
