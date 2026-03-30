import AppKit
import SwiftUI

enum ContentViewHelpers {
    static var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.04),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TimerStore

    @State private var hours = 0
    @State private var minutes = 1
    @State private var seconds = 0
    @State private var memoDraft = ""
    @State private var pendingMemoImageData: Data?
    @State private var pendingMemoImageFilename: String?
    @State private var selectedTimerIDs: Set<UUID> = []

    private var selectedTimerCount: Int {
        let activeTimerIDs = Set(store.timers.map(\.id))
        return selectedTimerIDs.intersection(activeTimerIDs).count
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                HeaderSection()

                CreateTimerSection(
                    hours: $hours,
                    minutes: $minutes,
                    seconds: $seconds
                )

                timerListSection

                GroupControlSection()

                AIConsoleSettingsSection()

                FloatingMemoSection(
                    memoDraft: $memoDraft,
                    pendingMemoImageData: $pendingMemoImageData,
                    pendingMemoImageFilename: $pendingMemoImageFilename
                )
            }
            .padding(28)
        }
        .background(
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.10)
                LinearGradient(
                    colors: [
                        Color(red: 0.09, green: 0.12, blue: 0.18).opacity(0.6),
                        Color(red: 0.08, green: 0.08, blue: 0.10),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .frame(minWidth: 620, idealWidth: 680, minHeight: 780, idealHeight: 860)
    }

    @ViewBuilder
    private var timerListSection: some View {
        if !store.timers.isEmpty || !store.groups.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("내 타이머")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("개별 타이머와 묶음을 한눈에 확인하고 동시에 제어합니다.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.64))
                    }

                    Spacer()

                    Text("\(store.timers.count) timer\(store.timers.count > 1 ? "s" : "")")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }

                ForEach(store.groups) { group in
                    TimerGroupRowView(
                        group: group,
                        timers: store.timers(inGroup: group.id)
                    )
                }

                ForEach(store.timers.filter { !store.groupedTimerIDs.contains($0.id) }) { timer in
                    TimerRowView(
                        timer: timer,
                        isSelected: selectedTimerIDs.contains(timer.id),
                        groupName: store.group(containing: timer.id)?.name,
                        onToggleSelection: { toggleSelection(timer.id) }
                    )
                }

                groupingBar
            }
            .padding(20)
            .background(ContentViewHelpers.cardBackground)
        }
    }

    @ViewBuilder
    private var groupingBar: some View {
        if selectedTimerCount > 0 {
            HStack(spacing: 12) {
                Text("\(selectedTimerCount)개 선택됨")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    let ids = Array(selectedTimerIDs)
                    if store.createGroup(with: ids) != nil {
                        selectedTimerIDs.removeAll()
                    }
                } label: {
                    Label("묶음 만들기", systemImage: "rectangle.3.group.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .disabled(selectedTimerCount < 2)

                Button {
                    selectedTimerIDs.removeAll()
                } label: {
                    Label("선택 해제", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(SecondaryActionButtonStyle())
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.12, green: 0.18, blue: 0.24).opacity(0.64))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(red: 0.63, green: 0.90, blue: 1.0).opacity(0.28), lineWidth: 1)
            )
        }
    }

    private func toggleSelection(_ timerID: UUID) {
        if selectedTimerIDs.contains(timerID) {
            selectedTimerIDs.remove(timerID)
        } else {
            selectedTimerIDs.insert(timerID)
        }
    }
}
