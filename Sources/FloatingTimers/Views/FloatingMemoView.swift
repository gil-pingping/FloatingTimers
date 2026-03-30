import AppKit
import SwiftUI

private enum FloatingMemoMetrics {
    static let minimizedWidth: CGFloat = 150
    static let minimizedHeight: CGFloat = 42
    static let transcriptCornerRadius: CGFloat = 18
}

struct FloatingMemoView: View {
    @EnvironmentObject private var store: TimerStore

    let memoID: UUID

    @State private var isHovering = false
    @State private var draftQuestion = ""
    @State private var resizeOriginSize: CGSize?

    static func preferredSize(for memo: MemoItem, isMinimized: Bool) -> CGSize {
        if isMinimized {
            return CGSize(width: FloatingMemoMetrics.minimizedWidth, height: FloatingMemoMetrics.minimizedHeight)
        }

        return MemoItem.clampedExpandedSize(memo.expandedSize, hasImage: memo.hasImage)
    }

    private var memo: MemoItem? {
        store.memo(for: memoID)
    }

    private var isMinimized: Bool {
        store.minimizedMemoIDs.contains(memoID)
    }

    var body: some View {
        Group {
            if let memo {
                content(for: memo)
                    .contextMenu {
                        if isMinimized {
                            Button("복원") {
                                store.restoreMemoHUD(memo.id)
                            }
                        } else {
                            Button("최소화") {
                                store.minimizeMemoHUD(memo.id)
                            }
                        }

                        Divider()

                        Button("메인 UI 열기") {
                            NotificationCenter.default.post(name: .showMainWindow, object: nil)
                        }

                        Divider()

                        Button("글자 크게") {
                            store.increaseMemoFontSize(memo.id)
                        }
                        .disabled(memo.fontSize >= MemoItem.maximumFontSize)

                        Button("글자 작게") {
                            store.decreaseMemoFontSize(memo.id)
                        }
                        .disabled(memo.fontSize <= MemoItem.minimumFontSize)

                        Button("글자 기본값") {
                            store.setMemoFontSize(memo.id, size: MemoItem.defaultFontSize)
                        }
                        .disabled(abs(memo.fontSize - MemoItem.defaultFontSize) < 0.01)

                        Divider()

                        Button("메모 삭제", role: .destructive) {
                            store.removeMemo(memo.id)
                        }
                    }
                    .onHover { isHovering = $0 }
                    .opacity(store.floatingOpacity)
            } else {
                Color.clear.frame(width: 280, height: 240)
            }
        }
    }

    @ViewBuilder
    private func content(for memo: MemoItem) -> some View {
        if isMinimized {
            minimizedBody(for: memo)
                .contentShape(Capsule())
                .onTapGesture {
                    store.restoreMemoHUD(memo.id)
                    store.revealMemo(memo.id)
                }
                .frame(
                    width: Self.preferredSize(for: memo, isMinimized: true).width,
                    height: Self.preferredSize(for: memo, isMinimized: true).height
                )
        } else {
            expandedBody(for: memo)
                .frame(
                    width: Self.preferredSize(for: memo, isMinimized: false).width,
                    height: Self.preferredSize(for: memo, isMinimized: false).height
                )
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            store.markMemoFocused(memo.id)
                        }
                )
        }
    }

    private func expandedBody(for memo: MemoItem) -> some View {
        let accent = accentColor(for: memo)

        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black.opacity(0.62))

            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .opacity(0.28)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(accent.opacity(0.14))

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(accent.opacity(0.12), lineWidth: 1)

            VStack(alignment: .leading, spacing: 12) {
                answerSection(for: memo)
                questionComposer(for: memo)
            }
            .padding(14)

            if isHovering {
                FloatingCornerButton(systemImage: "minus") {
                    store.minimizeMemoHUD(memo.id)
                }
                .padding(12)
                .transition(.opacity.combined(with: .scale))
            }

            resizeHandle(for: memo)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 20, y: 12)
    }

    private func answerSection(for memo: MemoItem) -> some View {
        let accent = accentColor(for: memo)
        let scrollIdentity = memo.latestResponseEntry?.id.uuidString ?? "empty-\(memo.assistantStatus.rawValue)"

        return ScrollView {
            Text(latestResponseText(for: memo))
                .font(.system(size: memo.fontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(latestResponseForegroundColor(for: memo))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
        }
        .id(scrollIdentity)
        .background(
            RoundedRectangle(cornerRadius: FloatingMemoMetrics.transcriptCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: FloatingMemoMetrics.transcriptCornerRadius, style: .continuous)
                .stroke(accent.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func questionComposer(for memo: MemoItem) -> some View {
        let accent = accentColor(for: memo)

        return HStack(spacing: 8) {
            TextField("질문 입력", text: $draftQuestion)
                .textFieldStyle(.plain)
                .font(.system(size: max(memo.fontSize - 1, MemoItem.minimumFontSize), weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .submitLabel(.send)
                .onSubmit {
                    submitQuestion(for: memo)
                }
                .disabled(memo.assistantStatus != .idle)

            Button(action: { submitQuestion(for: memo) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        memo.assistantStatus == .idle && !draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? accent.opacity(0.82)
                            : Color.white.opacity(0.16)
                    )
            }
            .buttonStyle(.plain)
            .disabled(memo.assistantStatus != .idle || draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.08), lineWidth: 1)
        )
    }

    private func resizeHandle(for memo: MemoItem) -> some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                ZStack {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(isHovering ? 0.48 : 0.20))
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .padding(.trailing, 8)
                .padding(.bottom, 8)
                .overlay(
                    MemoResizeHandleRepresentable(
                        onDragChanged: { delta in
                            if resizeOriginSize == nil {
                                resizeOriginSize = memo.expandedSize
                            }

                            let base = resizeOriginSize ?? memo.expandedSize
                            store.resizeMemo(
                                memo.id,
                                to: CGSize(
                                    width: base.width + delta.width,
                                    height: base.height + delta.height
                                )
                            )
                        },
                        onDragEnded: {
                            resizeOriginSize = nil
                        }
                    )
                )
            }
        }
    }

    private func minimizedBody(for memo: MemoItem) -> some View {
        let accent = accentColor(for: memo)

        return ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(Capsule())
                .opacity(0.42)

            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.56))

            Capsule(style: .continuous)
                .fill(accent.opacity(0.12))

            HStack(spacing: 8) {
                Image(systemName: memo.assistantStatus == .streaming ? "ellipsis.message.fill" : "text.bubble")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent.opacity(0.72))

                Text(memo.displayTitle)
                    .font(.system(size: max(memo.fontSize - 1, MemoItem.minimumFontSize), weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(accent.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)
    }

    private func submitQuestion(for memo: MemoItem) {
        let trimmed = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        draftQuestion = ""
        store.submitTextPrompt(trimmed, to: memo.id)
    }

    private func latestResponseText(for memo: MemoItem) -> String {
        if let latestResponseEntry = memo.latestResponseEntry {
            let trimmed = latestResponseEntry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if memo.assistantStatus == .requesting || memo.assistantStatus == .streaming || memo.assistantStatus == .capturing {
            return "응답 대기 중..."
        }

        return "답변 없음"
    }

    private func latestResponseForegroundColor(for memo: MemoItem) -> Color {
        guard let latestResponseEntry = memo.latestResponseEntry else {
            if memo.assistantStatus == .requesting || memo.assistantStatus == .streaming || memo.assistantStatus == .capturing {
                return accentColor(for: memo).opacity(0.88)
            }

            return .white.opacity(0.34)
        }

        switch latestResponseEntry.role {
        case .systemError:
            return Color(red: 1.0, green: 0.58, blue: 0.52)
        default:
            return .white.opacity(0.92)
        }
    }

    private func accentColor(for memo: MemoItem) -> Color {
        Color(
            red: memo.tint.red,
            green: memo.tint.green,
            blue: memo.tint.blue,
            opacity: memo.tint.alpha
        )
    }
}

private struct MemoResizeHandleRepresentable: NSViewRepresentable {
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> MemoResizeHandleNSView {
        let view = MemoResizeHandleNSView()
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: MemoResizeHandleNSView, context: Context) {
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

private final class MemoResizeHandleNSView: NSView {
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private var dragStartLocation: NSPoint?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = screenLocation(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartLocation else {
            return
        }

        let currentLocation = screenLocation(for: event)
        let delta = CGSize(
            width: currentLocation.x - dragStartLocation.x,
            height: dragStartLocation.y - currentLocation.y
        )
        onDragChanged?(delta)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        onDragEnded?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window else {
            return event.locationInWindow
        }

        return window.convertPoint(toScreen: event.locationInWindow)
    }
}
