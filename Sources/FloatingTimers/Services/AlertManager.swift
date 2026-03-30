import AppKit
import Foundation
import UserNotifications

@MainActor
protocol TimerAlerting: AnyObject {
    func requestAuthorizationIfNeeded() async
    func notifyTimerFinished(_ timer: TimerItem)
}

@MainActor
final class AlertManager: TimerAlerting {
    private var authorizationRequested = false
    private var lastSoundDate = Date.distantPast
    private let supportsSystemNotifications = Bundle.main.bundleURL.pathExtension == "app"

    func requestAuthorizationIfNeeded() async {
        guard supportsSystemNotifications, !authorizationRequested else {
            return
        }

        authorizationRequested = true
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The app should still work with local sound and visual emphasis even if this fails.
        }
    }

    func notifyTimerFinished(_ timer: TimerItem) {
        playAlertSoundIfNeeded()
        guard supportsSystemNotifications else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(timer.name) 완료"
        content.body = "\(timer.configuredDurationText) 타이머가 0초가 되었습니다."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    private func playAlertSoundIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastSoundDate) > 0.35 else {
            return
        }

        lastSoundDate = now

        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
