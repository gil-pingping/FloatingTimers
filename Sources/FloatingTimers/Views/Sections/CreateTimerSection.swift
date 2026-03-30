import SwiftUI

struct CreateTimerSection: View {
    @EnvironmentObject private var store: TimerStore

    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int

    private var totalSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    private var presets: [TimerPreset] {
        [
            TimerPreset(title: "5분", subtitle: "Quick", hours: 0, minutes: 5, seconds: 0, tint: Color(red: 0.62, green: 0.92, blue: 1.0)),
            TimerPreset(title: "10분", subtitle: "Sprint", hours: 0, minutes: 10, seconds: 0, tint: Color(red: 0.73, green: 0.91, blue: 0.70)),
            TimerPreset(title: "25분", subtitle: "Focus", hours: 0, minutes: 25, seconds: 0, tint: Color(red: 1.0, green: 0.78, blue: 0.48)),
            TimerPreset(title: "45분", subtitle: "Deep", hours: 0, minutes: 45, seconds: 0, tint: Color(red: 1.0, green: 0.62, blue: 0.56)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("새 타이머 추가")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("직접 시간을 맞추거나 프리셋으로 바로 채워서 HUD를 빠르게 만들 수 있습니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Text(totalSeconds == 0 ? "0초" : DurationFormatter.koreanLabel(totalSeconds: totalSeconds))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            HStack(spacing: 14) {
                TimeValueField(title: "시간", value: $hours, range: 0 ... 23)
                TimeValueField(title: "분", value: $minutes, range: 0 ... 59)
                TimeValueField(title: "초", value: $seconds, range: 0 ... 59)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("빠른 프리셋")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer()

                    Text("자주 쓰는 시간")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.42))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(presets) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            TimerPresetChip(preset: preset)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(totalSeconds == 0 ? "최소 1초 이상 설정해 주세요." : "추가하면 작은 원형 HUD 타이머가 바로 생성됩니다.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))

                Spacer()

                Button {
                    _ = store.addTimer(hours: hours, minutes: minutes, seconds: seconds)
                } label: {
                    Label("타이머 만들기", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(totalSeconds == 0)
            }
        }
        .padding(20)
        .background(ContentViewHelpers.cardBackground)
    }

    private func applyPreset(_ preset: TimerPreset) {
        hours = preset.hours
        minutes = preset.minutes
        seconds = preset.seconds
    }
}
