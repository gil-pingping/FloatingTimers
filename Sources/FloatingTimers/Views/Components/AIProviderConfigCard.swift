import SwiftUI

struct AIProviderConfigCard: View {
    let title: String
    let isActive: Bool
    @Binding var modelText: String
    @Binding var keyText: String
    @Binding var selectedSlot: Int
    let filledSlots: Set<Int>
    let tint: Color

    private var slotColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            AISettingsField(title: "Model", text: $modelText, placeholder: "model name")
            slotSection
            AISettingsField(
                title: "API Key \(selectedSlot + 1)",
                text: $keyText,
                placeholder: "paste API key",
                isSecure: true
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isActive ? Color.white.opacity(0.07) : Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isActive ? tint.opacity(0.30) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Text(isActive ? "ACTIVE" : "READY")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(tint.opacity(0.14))
                )
        }
    }

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key Slots")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                Spacer()

                Text("현재 \(selectedSlot + 1)번")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(tint.opacity(0.88))
            }

            LazyVGrid(columns: slotColumns, spacing: 8) {
                ForEach(0 ..< AISettingsSnapshot.maxKeySlots, id: \.self) { slot in
                    slotButton(slot)
                }
            }
        }
    }

    private func slotButton(_ slot: Int) -> some View {
        let isSelected = slot == selectedSlot
        let isFilled = filledSlots.contains(slot)

        return Button {
            selectedSlot = slot
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isFilled ? tint.opacity(0.92) : Color.white.opacity(0.14))
                    .frame(width: 6, height: 6)

                Text("\(slot + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .black : .white.opacity(0.82))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? tint.opacity(0.92) : Color.black.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? tint.opacity(0.16) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AISettingsField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var isSecure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.18))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }
}
