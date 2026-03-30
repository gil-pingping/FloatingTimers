import SwiftUI

struct TimerPreset: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let hours: Int
    let minutes: Int
    let seconds: Int
    let tint: Color
}

struct TimerPresetChip: View {
    let preset: TimerPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preset.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(preset.subtitle.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(preset.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(preset.tint.opacity(0.24), lineWidth: 1)
        )
    }
}
