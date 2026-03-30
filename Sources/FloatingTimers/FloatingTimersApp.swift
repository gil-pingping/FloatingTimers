import AppKit
import SwiftUI

@MainActor
final class MainWindowBridge {
    weak var mainWindow: NSWindow?
    var openMainWindowAction: (() -> Void)?

    func register(window: NSWindow?) {
        guard let window, !(window is FloatingTimerPanel) else {
            return
        }

        mainWindow = window
    }

    func showMainWindow() {
        openMainWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
        bringMainWindowToFront()

        DispatchQueue.main.async { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    private func bringMainWindowToFront() {
        let window = mainWindow ?? NSApp.windows.first(where: { !($0 is FloatingTimerPanel) })
        mainWindow = window
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
    }
}

@main
struct FloatingTimersApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var store: TimerStore
    private let windowManager: FloatingTimerWindowManager
    private let hotkeyManager: GlobalHotkeyManager
    private let mainWindowBridge: MainWindowBridge

    init() {
        let alertManager = AlertManager()
        let settingsStore = PersistentAISettingsStore()
        let appStateStore = FileAppStateStore()
        let captureService = ScreenCaptureService()
        let visionAssistantService = VisionAssistantService()
        let memoTranscriptStore = FileMemoTranscriptStore()
        let hotkeyManager = GlobalHotkeyManager()
        let mainWindowBridge = MainWindowBridge()
        let store = TimerStore(
            alertManager: alertManager,
            settingsStore: settingsStore,
            appStateStore: appStateStore,
            screenCaptureService: captureService,
            visionAssistantService: visionAssistantService,
            memoTranscriptStore: memoTranscriptStore
        )
        store.seedDefaultSetupIfNeeded()
        let windowManager = FloatingTimerWindowManager()
        _store = StateObject(wrappedValue: store)
        self.windowManager = windowManager
        self.hotkeyManager = hotkeyManager
        self.mainWindowBridge = mainWindowBridge

        windowManager.bind(to: store)
        hotkeyManager.onCaptureRequested = { [weak store] in
            Task { @MainActor in
                store?.handleCaptureHotkey()
            }
        }
        hotkeyManager.registerCaptureHotkey()
        appDelegate.onApplicationDidResignActive = { [weak store] in
            Task { @MainActor in
                store?.handleApplicationDidResignActive()
            }
        }
        appDelegate.onApplicationWillTerminate = { [weak store] in
            Task { @MainActor in
                store?.handleApplicationWillTerminate()
            }
        }
        appDelegate.onShowMainWindowRequested = { [mainWindowBridge] in
            mainWindowBridge.showMainWindow()
        }
    }

    var body: some Scene {
        WindowGroup("멀티 타이머 + 메모", id: "main") {
            MainWindowSceneView(bridge: mainWindowBridge)
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("새 타이머 추가") {
                    _ = store.addTimer(hours: 0, minutes: 1, seconds: 0)
                }
                .keyboardShortcut("n")

                Button("새 메모 추가") {
                    _ = store.addMemo()
                    store.setFloatingHUDsVisible(true)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandMenu("플로팅") {
                Button(store.areFloatingHUDsVisible ? "플로팅 HUD 끄기" : "플로팅 HUD 켜기") {
                    store.toggleFloatingHUDsVisibility()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("모두 복원") {
                    store.restoreAllFloatingUI()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

private struct MainWindowSceneView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: TimerStore

    let bridge: MainWindowBridge

    var body: some View {
        ContentView()
            .frame(minWidth: 620, minHeight: 560)
            .task {
                await store.prepareAlerts()
            }
            .background(
                MainWindowAccessor { window in
                    bridge.register(window: window)
                }
            )
            .onAppear {
                bridge.openMainWindowAction = {
                    openWindow(id: "main")
                }
            }
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onResolve: onResolve)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.scheduleResolution()
    }

    final class TrackingView: NSView {
        private let onResolve: (NSWindow?) -> Void

        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduleResolution()
        }

        func scheduleResolution() {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                self.onResolve(self.window)
            }
        }
    }
}
