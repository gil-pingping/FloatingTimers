import AppKit
import SwiftUI

struct HeaderSection: View {
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FLOATING HUD")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.00))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                Text("멀티 플로팅 타이머 + 메모")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("원형 타이머와 AI 플로팅 메모를 같이 띄워 두고, 화면 캡처 질문과 답변을 같은 카드에 계속 누적할 수 있게 정리했습니다.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("완전 종료", systemImage: "power")
            }
            .buttonStyle(DeleteActionButtonStyle())
        }
    }
}
