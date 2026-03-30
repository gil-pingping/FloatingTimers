import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        Color(
                            red: configuration.isPressed ? 0.56 : 0.67,
                            green: configuration.isPressed ? 0.82 : 0.92,
                            blue: configuration.isPressed ? 0.89 : 0.96
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct DeleteActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.22 : 0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.red.opacity(0.24), lineWidth: 1)
            )
    }
}
