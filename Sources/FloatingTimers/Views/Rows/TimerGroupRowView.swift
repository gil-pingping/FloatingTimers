import SwiftUI

struct TimerGroupRowView: View {
    @EnvironmentObject private var store: TimerStore

    let group: TimerGroup
    let timers: [TimerItem]

    private var hasFinishedTimers: Bool {
        timers.contains(where: \.isFinished)
    }

    private var floatingSummary: String {
        if !store.areFloatingHUDsVisible {
            return "그룹 HUD가 현재 꺼져 있습니다. 전역 HUD를 다시 켜면 같은 위치에서 복귀합니다."
        }

        if store.minimizedGroupIDs.contains(group.id) {
            return "이 그룹 HUD는 최소화된 캡슐 상태입니다. 캡슐을 클릭하면 다시 펼쳐집니다."
        }

        return "이 묶음은 하나의 플로팅 HUD로 표시되고, hover 최소화와 우클릭 메뉴를 지원합니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("\(timers.count)개")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.0))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }

                    Text(floatingSummary)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                }

                Spacer()

                Button("그룹 해제") {
                    store.ungroup(group.id)
                }
                .buttonStyle(DeleteActionButtonStyle())
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                ForEach(timers) { timer in
                    GroupMemberChip(timer: timer)
                }
            }

            HStack(spacing: 10) {
                Button("시작") {
                    store.startGroup(group.id)
                }
                .buttonStyle(PrimaryActionButtonStyle())

                Button("멈춤") {
                    store.pauseGroup(group.id)
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("초기화") {
                    store.resetGroup(group.id)
                }
                .buttonStyle(SecondaryActionButtonStyle())

                Button("재시작") {
                    store.restartGroup(group.id)
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(hasFinishedTimers ? Color(red: 0.44, green: 0.08, blue: 0.09).opacity(0.18) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(hasFinishedTimers ? Color.red.opacity(0.34) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
