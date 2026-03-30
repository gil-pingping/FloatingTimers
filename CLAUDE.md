# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Build:**
```bash
swift build -c release --product FloatingTimers
# Or use the full build script that creates the .app bundle:
./build-app.sh
```

**Test:**
```bash
swift test
# Run a single test:
swift test --filter TimerStoreTests/testMethodName
```

**Debug build:**
```bash
swift build --product FloatingTimers
```

The build script (`build-app.sh`) produces `dist/FloatingTimers.app/` with ad-hoc code signing.

## Architecture

**FloatingTimers** is a macOS accessory app (no Dock icon, `LSUIElement=true`) that provides floating timer panels and an AI-powered memo system. Built with Swift 6.2 targeting macOS 14.0+, mixing SwiftUI views with AppKit window management.

### Core Pattern: Model-View-Store

- **`TimerStore`** (`Stores/TimerStore.swift`) — `@MainActor` singleton, central state. All timers, groups, memos, and AI settings live here as `@Published` properties. SwiftUI views bind to this store.
- **`FloatingTimerWindowManager`** (`Windows/`) — Creates and manages `NSPanel` subclasses for the floating UI. Panels are always-on-top, borderless, and persist across Spaces.
- **`FloatingTimersApp`** (`FloatingTimersApp.swift`) — `@main` entry point; initializes store, window manager, `GlobalHotkeyManager`, and `AppDelegate`.

### Key Subsystems

**Floating UI** — `FloatingTimerPanel` (NSPanel subclass) hosts SwiftUI views. Panels support multiple Spaces, full-screen apps, opacity control, and position persistence. The window manager coordinates three panel types: timers, memos, and a control panel.

**AI Integration** — `VisionAssistantService` streams responses from OpenAI (`gpt-4.1`) or Google Gemini (`gemini-2.5-flash`). `AISettingsStore` persists API keys (multiple slots per provider). `ScreenCaptureService` uses ScreenCaptureKit to capture the current screen for vision analysis.

**Persistence** — `AppStateStore` saves/restores app state. `MemoTranscriptStore` persists memo conversation history. `TimerStore` itself handles timer/memo persistence.

**Global Hotkey** — `GlobalHotkeyManager` registers `Ctrl+;` via Carbon framework for quick screen capture without app focus.

### Directory Layout

```
Sources/FloatingTimers/
├── Models/          # Codable data structures (TimerItem, MemoItem, AIProvider, etc.)
├── Stores/          # TimerStore — central @MainActor state
├── Services/        # External integrations, persistence, system APIs
├── Windows/         # AppKit NSPanel management
└── Views/           # SwiftUI components
Tests/FloatingTimersTests/
└── TimerStoreTests.swift   # Timer lifecycle, groups, notifications, opacity
Packaging/Info.plist        # App bundle metadata
build-app.sh                # Build + bundle + codesign script
```

### Important Notes

- Swift 6 strict concurrency is in use — all UI/store mutations must be on `@MainActor`.
- The UI strings are in Korean throughout the codebase.
- `LSUIElement=true` means no Dock icon; the app is controlled entirely through its floating panels.
- Screen recording permission is required at runtime for the capture feature.
