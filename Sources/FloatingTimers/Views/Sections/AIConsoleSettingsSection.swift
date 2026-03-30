import SwiftUI

struct AIConsoleSettingsSection: View {
    @EnvironmentObject private var store: TimerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI 설정 / 진단")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("응답 provider, 모델, 키 슬롯을 관리하고 현재 복구 상태와 연결 상태를 빠르게 확인합니다.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                }

                Spacer()

                Text(store.aiHotkeyDescription)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.63, green: 0.90, blue: 1.0))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Picker("Provider", selection: Binding(
                get: { store.aiProvider },
                set: { store.setAIProvider($0) }
            )) {
                ForEach(AIProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            Text(store.aiConfigurationSummary)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            diagnosticsPanel

            VStack(spacing: 12) {
                AIProviderConfigCard(
                    title: "OpenAI",
                    isActive: store.aiProvider == .openAI,
                    modelText: Binding(
                        get: { store.openAIModel },
                        set: { store.setOpenAIModel($0) }
                    ),
                    keyText: Binding(
                        get: { store.openAIAPIKey },
                        set: { store.setOpenAIAPIKey($0) }
                    ),
                    selectedSlot: Binding(
                        get: { store.selectedOpenAIKeySlot },
                        set: { store.setSelectedOpenAIKeySlot($0) }
                    ),
                    filledSlots: store.filledOpenAIKeySlots,
                    tint: Color(red: 0.63, green: 0.90, blue: 1.0)
                )

                AIProviderConfigCard(
                    title: "Gemini",
                    isActive: store.aiProvider == .gemini,
                    modelText: Binding(
                        get: { store.geminiModel },
                        set: { store.setGeminiModel($0) }
                    ),
                    keyText: Binding(
                        get: { store.geminiAPIKey },
                        set: { store.setGeminiAPIKey($0) }
                    ),
                    selectedSlot: Binding(
                        get: { store.selectedGeminiKeySlot },
                        set: { store.setSelectedGeminiKeySlot($0) }
                    ),
                    filledSlots: store.filledGeminiKeySlots,
                    tint: Color(red: 0.73, green: 0.91, blue: 0.70)
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("연결 확인")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.84))

                HStack(spacing: 10) {
                    Button("텍스트") {
                        store.runTextOnlyAISmokeTest()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())
                    .disabled(!store.hasActiveAIKey)
                    .opacity(store.hasActiveAIKey ? 1 : 0.5)

                    Button("캡처") {
                        store.runCaptureOnlySmokeTest()
                    }
                    .buttonStyle(SecondaryActionButtonStyle())

                    Button("캡처 + 응답") {
                        store.runCaptureAISmokeTest()
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(!store.hasActiveAIKey)
                    .opacity(store.hasActiveAIKey ? 1 : 0.5)
                }

                Text(store.aiSmokeStatus)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.14))
                    )
            }

            Text("단축키를 누르면 마지막으로 포커스한 메모를 대상으로 전체 화면을 캡처하고, 그 메모의 기본 프롬프트를 질문으로 사용합니다.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.54))
        }
        .padding(20)
        .background(ContentViewHelpers.cardBackground)
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiagnosticRow(
                title: "저장 상태",
                value: store.persistenceStatusMessage,
                tint: Color(red: 0.73, green: 0.91, blue: 0.70)
            )

            DiagnosticRow(
                title: "화면 기록 권한",
                value: store.screenCapturePermissionSummary,
                tint: store.screenCapturePermissionSummary == "허용됨"
                    ? Color(red: 0.63, green: 0.90, blue: 1.0)
                    : Color(red: 1.0, green: 0.78, blue: 0.48)
            )

            DiagnosticRow(
                title: "활성 키",
                value: store.activeAIKeySummary,
                tint: store.hasActiveAIKey
                    ? Color(red: 0.73, green: 0.91, blue: 0.70)
                    : Color(red: 1.0, green: 0.78, blue: 0.48)
            )

            DiagnosticRow(
                title: "플로팅 상태",
                value: store.floatingRecoverySummary,
                tint: Color(red: 1.0, green: 0.78, blue: 0.48)
            )

            DiagnosticRow(
                title: "최근 AI 오류",
                value: store.recentAIErrorSummary,
                tint: Color(red: 1.0, green: 0.62, blue: 0.56)
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
