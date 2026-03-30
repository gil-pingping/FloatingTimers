import SwiftUI

struct TimerRowView: View {
    @EnvironmentObject private var store: TimerStore

    let timer: TimerItem
    let isSelected: Bool
    let groupName: String?
    let onToggleSelection: () -> Void

    private var floatingSummary: String {
        if groupName != nil {
            if !store.areFloatingHUDsVisible {
                return "그룹 HUD가 현재 꺼져 있습니다. 전역 HUD를 다시 켜면 그룹 상태로 복귀합니다."
            }

            return "그룹에 묶여 있어 개별 원형 대신 그룹 HUD에서 같이 보입니다."
        }

        if !store.areFloatingHUDsVisible {
            return "플로팅 HUD가 현재 꺼져 있습니다. 필요할 때 전체 제어에서 다시 켤 수 있습니다."
        }

        if store.minimizedTimerIDs.contains(timer.id) {
            return "플로팅 HUD가 캡슐 형태로 최소화되어 있습니다. 클릭하면 다시 펼쳐집니다."
        }

        return "플로팅 HUD: 더블클릭 시작/멈춤, 우클릭 개별 메뉴, hover 최소화 지원"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(isSelected ? Color(red: 0.63, green: 0.90, blue: 1.0) : .white.opacity(0.34))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(timer.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if let groupName {
                            Text(groupName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.0))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }

                    Text("설정: \(timer.configuredDurationText)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))

                    Text(floatingSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                }

                Spacer()

                statusBadge
            }

            HStack(alignment: .firstTextBaseline) {
                Text(timer.remainingDurationText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer()

                Button("삭제") {
                    store.removeTimer(timer.id)
                }
                .buttonStyle(DeleteActionButtonStyle())
            }

            ProgressView(value: timer.progress)
                .progressViewStyle(.linear)
                .tint(timer.isFinished ? Color.orange : Color.white.opacity(0.88))

            HStack(spacing: 10) {
                Button(primaryActionLabel) {
                    primaryAction()
                }
                .buttonStyle(PrimaryActionButtonStyle())

                Button("초기화") {
                    store.reset(timer.id)
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("재시작") {
                    store.restart(timer.id)
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    isSelected
                        ? Color(red: 0.16, green: 0.22, blue: 0.27).opacity(0.52)
                        : (timer.isFinished ? Color(red: 0.50, green: 0.08, blue: 0.09).opacity(0.28) : Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    isSelected
                        ? Color(red: 0.63, green: 0.90, blue: 1.0).opacity(0.45)
                        : (timer.isFinished ? Color.red.opacity(0.62) : Color.white.opacity(0.08)),
                    lineWidth: 1
                )
        )
    }

    private var statusBadge: some View {
        Text(timer.state.label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.85))
            )
    }

    private var statusColor: Color {
        switch timer.state {
        case .idle:
            return .gray
        case .running:
            return .blue
        case .paused:
            return .yellow
        case .finished:
            return .orange
        }
    }

    private var primaryActionLabel: String {
        switch timer.state {
        case .running:
            return "멈춤"
        case .finished:
            return "다시 시작"
        case .idle, .paused:
            return "시작"
        }
    }

    private func primaryAction() {
        switch timer.state {
        case .running:
            store.pause(timer.id)
        case .finished:
            store.restart(timer.id)
        case .idle, .paused:
            store.start(timer.id)
        }
    }
}
