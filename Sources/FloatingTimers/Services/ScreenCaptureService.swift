import AppKit
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

struct CapturedScreenshot {
    let data: Data
    let filename: String
    let mimeType: String
}

protocol ScreenCaptureServing: Sendable {
    @MainActor
    func captureCurrentScreenJPEG() async throws -> CapturedScreenshot
}

enum ScreenCaptureServiceError: LocalizedError {
    case noDisplay
    case screenRecordingPermissionRequired
    case captureFailed(String)
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay:
            return "캡처할 화면을 찾지 못했습니다."
        case .screenRecordingPermissionRequired:
            return "화면 기록 권한이 아직 적용되지 않았습니다. 시스템 설정의 화면 기록(또는 화면 및 시스템 오디오 기록)에서 FloatingTimers를 허용한 뒤 앱을 완전히 종료하고 다시 실행하세요. 개발 중 새로 빌드한 앱은 macOS가 다른 앱으로 인식해 다시 허용이 필요할 수 있습니다."
        case let .captureFailed(message):
            return message
        case .encodeFailed:
            return "캡처 이미지를 변환하지 못했습니다."
        }
    }
}

struct UnavailableScreenCaptureService: ScreenCaptureServing, Sendable {
    @MainActor
    func captureCurrentScreenJPEG() async throws -> CapturedScreenshot {
        throw ScreenCaptureServiceError.captureFailed("이 환경에서는 화면 캡처 서비스가 연결되지 않았습니다.")
    }
}

final class ScreenCaptureService: ScreenCaptureServing, @unchecked Sendable {
    @MainActor
    func captureCurrentScreenJPEG() async throws -> CapturedScreenshot {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureServiceError.screenRecordingPermissionRequired
        }

        let shareableContent = try await SCShareableContent.current
        let mouseLocation = await MainActor.run { NSEvent.mouseLocation }
        guard let targetDisplay = display(containing: mouseLocation, from: shareableContent.displays) ?? shareableContent.displays.first else {
            throw ScreenCaptureServiceError.noDisplay
        }

        let filter = SCContentFilter(display: targetDisplay, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = true

        let cgImage: CGImage = try await withThrowingTaskGroup(of: CGImage.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                        if let image {
                            continuation.resume(returning: image)
                        } else {
                            continuation.resume(throwing: error ?? ScreenCaptureServiceError.captureFailed("화면 캡처에 실패했습니다."))
                        }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw ScreenCaptureServiceError.captureFailed("화면 캡처가 10초 안에 완료되지 않았습니다.")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        guard let imageData = jpegData(from: cgImage) else {
            throw ScreenCaptureServiceError.encodeFailed
        }

        return CapturedScreenshot(
            data: imageData,
            filename: "Capture-\(Int(Date().timeIntervalSince1970)).jpg",
            mimeType: "image/jpeg"
        )
    }

    private func display(containing point: CGPoint, from displays: [SCDisplay]) -> SCDisplay? {
        displays.first(where: { $0.frame.contains(point) })
    }

    private func jpegData(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.84]
        )
    }
}
