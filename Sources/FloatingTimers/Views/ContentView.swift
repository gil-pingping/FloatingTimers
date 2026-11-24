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

enum MainTab: String, CaseIterable, Identifiable {
    case timers = "타이머 스튜디오"
    case memos = "AI 메모 보드"
    case control = "시스템 설정"

    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .timers: return "stopwatch.fill"
        case .memos: return "sparkles.rectangle.stack.fill"
        case .control: return "gearshape.fill"
        }
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
    @State private var selectedTab: MainTab = .timers

    private var selectedTimerCount: Int {
        let activeTimerIDs = Set(store.timers.map(\.id))
        return selectedTimerIDs.intersection(activeTimerIDs).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상단 탭 스위처
            HStack(spacing: 12) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.systemImage)
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedTab == tab ? .black : .white.opacity(0.6))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? Color(red: 0.63, green: 0.90, blue: 1.0) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: selectedTab == tab ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("종료", systemImage: "power")
                }
                .buttonStyle(DeleteActionButtonStyle())
            }
            .padding(28)
            .background(Color.black.opacity(0.2))

            // 메인 컴포넌트 스크롤 뷰
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 22) {
                    switch selectedTab {
                    case .timers:
                        HeaderSection()
                        CreateTimerSection(
                            hours: $hours,
                            minutes: $minutes,
                            seconds: $seconds
                        )
                        timerListSection
                        
                    case .memos:
                        FloatingMemoSection(
                            memoDraft: $memoDraft,
                            pendingMemoImageData: $pendingMemoImageData,
                            pendingMemoImageFilename: $pendingMemoImageFilename
                        )
                        
                    case .control:
                        GroupControlSection()
                        AIConsoleSettingsSection()
                    }
                    
                    // 하단 여백 — 맨 아래 콘텐츠가 잘리지 않도록
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .id(selectedTab)
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
