import AppKit
import UniformTypeIdentifiers

enum PasteboardImageDetection {
    static let ctrlVAction = "text:\\x16"

    enum PasteAction: Equatable {
        case sendCtrlV
        case pasteFromClipboard
    }

    static func pasteAction(sendsCtrlVForImages: Bool, types: [NSPasteboard.PasteboardType]) -> PasteAction {
        sendsCtrlVForImages && shouldSendCtrlV(types: types) ? .sendCtrlV : .pasteFromClipboard
    }

    static func shouldSendCtrlV(types: [NSPasteboard.PasteboardType]) -> Bool {
        var hasImage = false
        for type in types {
            if isText(type) { return false }
            if isImage(type) { hasImage = true }
        }
        return hasImage
    }

    private static func isText(_ type: NSPasteboard.PasteboardType) -> Bool {
        if type == .string || type == .fileURL { return true }
        return UTType(type.rawValue)?.conforms(to: .plainText) ?? false
    }

    private static func isImage(_ type: NSPasteboard.PasteboardType) -> Bool {
        if type == .png || type == .tiff { return true }
        return UTType(type.rawValue)?.conforms(to: .image) ?? false
    }
}
