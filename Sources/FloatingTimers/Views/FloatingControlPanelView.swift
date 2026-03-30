import AppKit
import SwiftUI

struct FloatingControlPanelView: View {
    @EnvironmentObject private var store: TimerStore

    static func preferredSize(for mode: FloatingPanelMode) -> NSSize {
        switch mode {
        case .expanded:
            return NSSize(width: 252, height: 102)
        case .minimized:
            return NSSize(width: 178, height: 38)
        case .hidden:
            return NSSize(width: 1, height: 1)
        }
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { store.floatingOpacity },
            set: { store.setFloatingOpacity($0) }
        )
    }

    private var primaryPlaybackTitle: String {
        store.timers.contains(where: { $0.state == .running }) ? "멈춤" : "시작"
    }

    private var primaryPlaybackIcon: String {
        store.timers.contains(where: { $0.state == .running }) ? "pause.fill" : "play.fill"
    }

    private var primaryPlaybackSubtitle: String {
        store.timers.contains(where: { $0.state == .running }) ? "전체 일시정지" : "전체 시작"
    }

    private var hudTitle: String {
        store.areFloatingHUDsVisible ? "HUD ON" : "HUD OFF"
    }

    private var hudSubtitle: String {
        store.areFloatingHUDsVisible ? "잠시 숨기기" : "다시 표시"
    }

    var body: some View {
        Group {
            switch store.controlPanelMode {
            case .expanded:
                expandedBody
                    .frame(width: 252, height: 102)
            case .minimized:
                minimizedBody
                    .frame(width: 178, height: 38)
            case .hidden:
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
    }

    private var expandedBody: some View {
        panelChrome(cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.57, green: 0.88, blue: 1.0))
                            .frame(width: 7, height: 7)

                        Text(summaryText)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.82))

                    Spacer()

                    FloatingPillLabel(
                        label: "SAFE",
                        systemImage: "shield.fill"
                    )

                    FloatingCircleButton(systemImage: "minus") {
                        store.setControlPanelMode(.minimized)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        performPrimaryPlaybackAction()
                    } label: {
                        RemoteActionButton(
                            title: primaryPlaybackTitle,
                            subtitle: primaryPlaybackSubtitle,
                            systemImage: primaryPlaybackIcon,
                            tint: Color(red: 0.63, green: 0.90, blue: 1.0)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(store.timers.isEmpty)
                    .opacity(store.timers.isEmpty ? 0.45 : 1)

                    Button {
                        store.toggleFloatingHUDsVisibility()
                    } label: {
                        RemoteActionButton(
                            title: hudTitle,
                            subtitle: hudSubtitle,
                            systemImage: store.areFloatingHUDsVisible ? "eye.fill" : "eye.slash.fill",
                            tint: store.areFloatingHUDsVisible ? Color(red: 0.73, green: 0.91, blue: 0.70) : Color(red: 1.0, green: 0.62, blue: 0.56)
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    FloatingPillButton(label: "복원", systemImage: "arrow.clockwise.circle.fill") {
                        store.restoreAllFloatingUI()
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.62))

                        Slider(value: opacityBinding, in: 0.2 ... 1.0)
                            .frame(width: 78)
                            .tint(Color(red: 0.67, green: 0.92, blue: 1.0))

                        Text("\(Int(store.floatingOpacity * 100))")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.84))
                            .frame(width: 24, alignment: .trailing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.09), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var minimizedBody: some View {
        panelChrome(cornerRadius: 18) {
            HStack(spacing: 7) {
                FloatingPillButton(
                    label: hudTitle,
                    systemImage: store.areFloatingHUDsVisible ? "eye.fill" : "eye.slash.fill"
                ) {
                    store.toggleFloatingHUDsVisibility()
                }

                FloatingPillLabel(
                    label: "SAFE",
                    systemImage: "shield.fill"
                )

                Text(summaryText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(1)

                Spacer(minLength: 0)

                FloatingCircleButton(systemImage: "arrow.clockwise") {
                    store.restoreAllFloatingUI()
                }

                FloatingCircleButton(systemImage: "arrow.up.left.and.arrow.down.right") {
                    store.setControlPanelMode(.expanded)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
    }

    private var summaryText: String {
        if store.areFloatingHUDsVisible {
            return "\(store.displayedFloatingHUDCount) live · \(store.minimizedFloatingHUDCount) mini · safe"
        }

        return "HUD off · \(store.totalFloatingHUDCount) ready · safe"
    }

    private func performPrimaryPlaybackAction() {
        if store.timers.contains(where: { $0.state == .running }) {
            store.pauseAll()
        } else {
            store.startAll()
        }
    }

    private func panelChrome<Content: View>(cornerRadius: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .opacity(0.82)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.13, blue: 0.16).opacity(0.90),
                            Color(red: 0.07, green: 0.09, blue: 0.11).opacity(0.94),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
    }
}

private struct FloatingIconButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))

                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct RemoteActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)

            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct FloatingPillButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))

                Text(label)
                    .font(.system(size: 10, weight: .black, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FloatingPillLabel: View {
    let label: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))

            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.73, green: 0.91, blue: 0.70))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct FloatingCircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "\(systemImage).circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.88), Color.black.opacity(0.34))
        }
        .buttonStyle(.plain)
    }
}
