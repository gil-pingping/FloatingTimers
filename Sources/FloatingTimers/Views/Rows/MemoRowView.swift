import AppKit
import SwiftUI

struct MemoRowView: View {
    @EnvironmentObject private var store: TimerStore

    let memo: MemoItem
    @State private var draftInstruction = ""
    @State private var colorSampler: NSColorSampler?

    private var floatingSummary: String {
        if !store.areFloatingHUDsVisible {
            return "플로팅 UI가 현재 꺼져 있습니다. 다시 보이기로 바꾸면 같은 메모 카드가 바로 복귀합니다."
        }

        if store.minimizedMemoIDs.contains(memo.id) {
            return "메모 카드가 캡슐 형태로 접혀 있습니다. 여기서 바로 다시 펼칠 수 있습니다."
        }

        return "\(store.aiHotkeyDescription) 로 현재 화면을 캡처해 이 메모에 질문/답변을 누적할 수 있습니다."
    }

    private var primaryButtonTitle: String {
        if !store.areFloatingHUDsVisible || store.minimizedMemoIDs.contains(memo.id) {
            return "열기"
        }

        return "최소화"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(memo.displayTitle)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if memo.hasImage {
                            Text("IMAGE")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 1.0, green: 0.84, blue: 0.48))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                    }

                    Text(memo.statusSummary)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)

                    Text(memo.previewLine)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(2)

                    Text(floatingSummary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.54))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(store.aiProvider.label)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.0))

                    Text(store.activeAIModel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 10) {
                Button(primaryButtonTitle) {
                    toggleVisibility()
                }
                .buttonStyle(PrimaryActionButtonStyle())

                if memo.hasImage {
                    Button("참고 이미지 제거") {
                        store.removeMemoImage(memo.id)
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                Button("삭제") {
                    store.removeMemo(memo.id)
                }
                .buttonStyle(DeleteActionButtonStyle())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("기본 프롬프트")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))

                    Spacer()

                    Button(action: sampleMemoColor) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(
                                    Color(
                                        red: memo.tint.red,
                                        green: memo.tint.green,
                                        blue: memo.tint.blue,
                                        opacity: memo.tint.alpha
                                    )
                                )
                                .frame(width: 10, height: 10)

                            Image(systemName: "eyedropper")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )

                    if draftInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("비워두면 기본 분석 문구를 사용합니다.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.34))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }

                    TextEditor(text: $draftInstruction)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.clear)
                }
                .frame(height: 92)
                .onChange(of: draftInstruction) { _, newValue in
                    store.updateMemoInstruction(memo.id, text: newValue)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.22, green: 0.18, blue: 0.09).opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            draftInstruction = memo.instructionText
        }
        .onChange(of: memo.instructionText) { _, newValue in
            if draftInstruction != newValue {
                draftInstruction = newValue
            }
        }
    }

    private var statusColor: Color {
        switch memo.assistantStatus {
        case .idle:
            return Color(red: 0.73, green: 0.91, blue: 0.70)
        case .capturing:
            return Color(red: 1.0, green: 0.84, blue: 0.48)
        case .requesting:
            return Color(red: 1.0, green: 0.62, blue: 0.56)
        case .streaming:
            return Color(red: 0.63, green: 0.90, blue: 1.0)
        }
    }

    private func toggleVisibility() {
        if !store.areFloatingHUDsVisible || store.minimizedMemoIDs.contains(memo.id) {
            store.revealMemo(memo.id)
        } else {
            store.minimizeMemoHUD(memo.id)
        }
    }

    private func sampleMemoColor() {
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { color in
            Task { @MainActor in
                defer { colorSampler = nil }
                guard let color else {
                    return
                }

                store.setMemoTint(memo.id, tint: MemoTint(nsColor: color))
            }
        }
    }
}
