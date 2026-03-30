import AppKit
import SwiftUI

struct GroupControlSection: View {
    @EnvironmentObject private var store: TimerStore

    private var floatingStatusMessage: String {
        let baseMessage: String

        if !store.areFloatingHUDsVisible {
            baseMessage = "플로팅 HUD가 꺼져 있습니다. 타이머와 메모는 유지되고, 필요할 때 한 번에 다시 켤 수 있습니다."
        } else if store.minimizedFloatingHUDCount > 0 {
            baseMessage = "\(store.minimizedFloatingHUDCount)개의 플로팅 카드가 접혀 있습니다. 캡슐 상태를 클릭하거나 여기서 모두 복원할 수 있습니다."
        } else {
            switch store.controlPanelMode {
            case .expanded:
                baseMessage = "플로팅 타이머, 메모, 컨트롤 패널이 모두 동작 중입니다."
            case .minimized:
                baseMessage = "컨트롤 패널이 슬림 스트립으로 접혀 있습니다. 화면 위에서 바로 HUD on/off와 복원이 가능합니다."
            case .hidden:
                baseMessage = "컨트롤 패널이 숨겨져 있습니다. 타이머와 메모는 각 카드에서 직접 조작할 수 있습니다."
            }
        }

        if store.isFloatingCaptureExcluded {
            return "\(baseMessage) 화면 공유와 녹화에서는 플로팅 UI가 캡처되지 않습니다."
        }

        return baseMessage
    }

    private var controlPanelButtonTitle: String {
        switch store.controlPanelMode {
        case .expanded:
            return "컨트롤 바 접기"
        case .minimized:
            return "컨트롤 바 펼치기"
        case .hidden:
            return "컨트롤 바 보이기"
        }
    }

    private var controlPanelTileSubtitle: String {
        switch store.controlPanelMode {
        case .expanded:
            return "화면 위 리모컨 접기"
        case .minimized:
            return "스트립을 다시 펼치기"
        case .hidden:
            return "숨긴 컨트롤 바 복구"
        }
    }

    private var controlPanelTileIcon: String {
        switch store.controlPanelMode {
        case .expanded:
            return "rectangle.compress.vertical"
        case .minimized:
            return "rectangle.expand.vertical"
        case .hidden:
            return "rectangle.on.rectangle"
        }
    }

    private var globalPlaybackTitle: String {
        store.timers.contains(where: { $0.state == .running }) ? "모두 멈춤" : "모두 시작"
    }

    private var globalPlaybackSubtitle: String {
        if store.timers.isEmpty {
            return "활성 타이머 없음"
        }

        return store.timers.contains(where: { $0.state == .running }) ? "지금 진행 중인 타이머 일시정지" : "모든 타이머를 한 번에 시작"
    }

    private var globalPlaybackIcon: String {
        store.timers.contains(where: { $0.state == .running }) ? "pause.fill" : "play.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("전체 제어 / 플로팅")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("자주 쓰는 조작은 크게, 덜 쓰는 조작은 보조 메뉴로 정리했습니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Text("\(store.totalFloatingHUDCount) floating")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            HStack(spacing: 8) {
                FloatingStatusChip(
                    label: store.areFloatingHUDsVisible ? "HUD" : "HUD OFF",
                    value: store.areFloatingHUDsVisible ? "\(store.displayedFloatingHUDCount) live" : "\(store.totalFloatingHUDCount) ready",
                    tint: store.areFloatingHUDsVisible ? Color(red: 0.63, green: 0.90, blue: 1.0) : Color(red: 1.0, green: 0.52, blue: 0.42)
                )

                FloatingStatusChip(
                    label: "MINI",
                    value: "\(store.minimizedFloatingHUDCount)",
                    tint: Color(red: 0.98, green: 0.83, blue: 0.42)
                )

                FloatingStatusChip(
                    label: "MEMO",
                    value: "\(store.memos.count)",
                    tint: Color(red: 1.0, green: 0.84, blue: 0.48)
                )

                FloatingStatusChip(
                    label: "PANEL",
                    value: store.controlPanelMode.label,
                    tint: Color.white.opacity(0.82)
                )

                FloatingStatusChip(
                    label: "SAFE",
                    value: "ON",
                    tint: Color(red: 0.73, green: 0.91, blue: 0.70)
                )
            }

            Text(floatingStatusMessage)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                Button {
                    store.toggleFloatingHUDsVisibility()
                } label: {
                    ControlActionTile(
                        title: store.areFloatingHUDsVisible ? "HUD 끄기" : "HUD 켜기",
                        subtitle: store.areFloatingHUDsVisible ? "화면 위 HUD를 잠시 숨기기" : "같은 상태 그대로 다시 표시",
                        systemImage: store.areFloatingHUDsVisible ? "eye.slash.fill" : "eye.fill",
                        tint: store.areFloatingHUDsVisible ? Color(red: 0.96, green: 0.62, blue: 0.58) : Color(red: 0.62, green: 0.92, blue: 1.0)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    store.restoreAllFloatingUI()
                } label: {
                    ControlActionTile(
                        title: "모두 복원",
                        subtitle: "접힌 HUD만 복구하고 컨트롤 바는 현재 상태 유지",
                        systemImage: "arrow.clockwise.circle.fill",
                        tint: Color(red: 0.73, green: 0.91, blue: 0.70)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    toggleControlPanelMode()
                } label: {
                    ControlActionTile(
                        title: controlPanelButtonTitle,
                        subtitle: controlPanelTileSubtitle,
                        systemImage: controlPanelTileIcon,
                        tint: Color.white.opacity(0.92)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Button {
                    performGlobalPlaybackAction()
                } label: {
                    Label(globalPlaybackTitle, systemImage: globalPlaybackIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(store.timers.isEmpty)

                Menu {
                    Button("모두 초기화") {
                        store.resetAll()
                    }

                    Button("모두 재시작") {
                        store.restartAll()
                    }

                    Divider()

                    Button("컨트롤 바 앞으로") {
                        store.setControlPanelMode(.expanded)
                        NotificationCenter.default.post(name: .showFloatingControlsPanel, object: nil)
                    }

                    if store.controlPanelMode == .hidden {
                        Button("컨트롤 바 보이기") {
                            store.setControlPanelMode(.expanded)
                            NotificationCenter.default.post(name: .showFloatingControlsPanel, object: nil)
                        }
                    } else {
                        Button("컨트롤 바 숨기기") {
                            store.setControlPanelMode(.hidden)
                        }
                    }
                } label: {
                    Label("보조 제어", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("플로팅 HUD 투명도")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(globalPlaybackSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Slider(
                    value: Binding(
                        get: { store.floatingOpacity },
                        set: { store.setFloatingOpacity($0) }
                    ),
                    in: 0.2 ... 1.0
                )
                .tint(Color(red: 0.67, green: 0.92, blue: 1.0))

                Text("\(Int(store.floatingOpacity * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 46, alignment: .trailing)
            }
        }
        .padding(20)
        .background(ContentViewHelpers.cardBackground)
    }

    private func toggleControlPanelMode() {
        switch store.controlPanelMode {
        case .expanded:
            store.setControlPanelMode(.minimized)
        case .minimized, .hidden:
            store.setControlPanelMode(.expanded)
            NotificationCenter.default.post(name: .showFloatingControlsPanel, object: nil)
        }
    }

    private func performGlobalPlaybackAction() {
        if store.timers.contains(where: { $0.state == .running }) {
            store.pauseAll()
        } else {
            store.startAll()
        }
    }
}
