import SwiftUI

struct FloatingMemoSection: View {
    @EnvironmentObject private var store: TimerStore

    @Binding var memoDraft: String
    @Binding var pendingMemoImageData: Data?
    @Binding var pendingMemoImageFilename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 플로팅 메모")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("메인 창에서 기본 Prompt를 관리하고, 플로팅 카드에서는 질문과 답변만 빠르게 주고받도록 정리했습니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Text("\(store.memos.count) memos")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if memoDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("이 메모가 화면 캡처를 해석할 기본 Prompt입니다. 비워두면 기본 분석 문구를 사용합니다.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.36))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                }

                TextEditor(text: $memoDraft)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.clear)
            }
            .frame(height: 128)

            HStack(spacing: 10) {
                Button {
                    pickComposerImage()
                } label: {
                    Label(pendingMemoImageData == nil ? "참고 이미지 첨부" : "참고 이미지 바꾸기", systemImage: "photo")
                }
                .buttonStyle(SecondaryActionButtonStyle())

                if let pendingMemoImageFilename {
                    Text(pendingMemoImageFilename)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }

                if pendingMemoImageData != nil {
                    Button("이미지 제거") {
                        clearComposerImage()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                }

                Spacer()

                Button {
                    createMemo()
                } label: {
                    Label("AI 메모 만들기", systemImage: "terminal.badge.plus")
                }
                .buttonStyle(PrimaryActionButtonStyle())
            }

            if store.memos.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("아직 메모가 없습니다.")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("메모를 만들면 별도 플로팅 AI 카드가 뜨고, 답변 확인과 빠른 질문은 플로팅에서, 기본 Prompt 관리는 여기서 합니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))

                    Text("기본 단축키: \(store.aiHotkeyDescription)")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.0))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(store.memos) { memo in
                        MemoRowView(memo: memo)
                    }
                }
            }
        }
        .padding(20)
        .background(ContentViewHelpers.cardBackground)
    }

    private func pickComposerImage() {
        guard let selection = MemoImagePicker.pickImage() else {
            return
        }

        pendingMemoImageData = selection.data
        pendingMemoImageFilename = selection.filename
    }

    private func clearComposerImage() {
        pendingMemoImageData = nil
        pendingMemoImageFilename = nil
    }

    private func createMemo() {
        let memoID = store.addMemo(
            text: memoDraft,
            imageData: pendingMemoImageData,
            imageFilename: pendingMemoImageFilename
        )
        memoDraft = ""
        clearComposerImage()
        store.revealMemo(memoID)
    }
}
