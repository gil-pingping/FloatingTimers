import Carbon
import Foundation

final class GlobalHotkeyManager {
    static let hotkeyDescription = "Control + ;"

    private static let signature: OSType = 0x46544D52 // FTMR
    private static let captureHotkeyID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    var onCaptureRequested: (() -> Void)?

    func registerCaptureHotkey() {
        guard hotKeyRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()

                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if hotKeyID.signature == GlobalHotkeyManager.signature, hotKeyID.id == GlobalHotkeyManager.captureHotkeyID {
                    manager.onCaptureRequested?()
                }

                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.captureHotkeyID)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Semicolon),
            UInt32(controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }
}
