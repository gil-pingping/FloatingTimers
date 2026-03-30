import SwiftUI

struct TimeValueField: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 10) {
                TextField(title, value: $value, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 54)
                    .multilineTextAlignment(.center)

                Stepper("", value: $value, in: range)
                    .labelsHidden()
                    .tint(Color(red: 0.67, green: 0.92, blue: 1.0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity)
        .onChange(of: value) { _, newValue in
            value = min(max(newValue, range.lowerBound), range.upperBound)
        }
    }
}
