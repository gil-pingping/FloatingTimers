import AppKit
import Foundation
import UniformTypeIdentifiers

struct MemoImageSelection {
    let data: Data
    let filename: String
}

@MainActor
enum MemoImagePicker {
    static func pickImage() -> MemoImageSelection? {
        let panel = NSOpenPanel()
        panel.title = "메모에 첨부할 이미지 선택"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return MemoImageSelection(data: data, filename: url.lastPathComponent)
    }
}
