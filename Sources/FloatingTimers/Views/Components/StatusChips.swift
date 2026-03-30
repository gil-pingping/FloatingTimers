import SwiftUI

struct FloatingStatusChip: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(tint)

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

struct GroupMemberChip: View {
    let timer: TimerItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)

                Text(timer.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }

            Text(timer.remainingDurationText)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)

            Text(timer.state.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(timer.isFinished ? Color(red: 0.42, green: 0.06, blue: 0.08).opacity(0.24) : Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(timer.isFinished ? Color.red.opacity(0.32) : Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch timer.state {
        case .idle:
            return .white.opacity(0.28)
        case .running:
            return Color(red: 0.63, green: 0.90, blue: 1.0)
        case .paused:
            return Color(red: 0.98, green: 0.82, blue: 0.44)
        case .finished:
            return .orange.opacity(0.92)
        }
    }
}

struct DiagnosticRow: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tint.opacity(0.92))
                .frame(width: 7, height: 7)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))

                Text(value)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
