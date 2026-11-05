import AppKit
import Testing
@testable import Ghostty

struct PasteboardImageDetectionTests {
    @Test func imageOnlySendsCtrlV() {
        #expect(PasteboardImageDetection.shouldSendCtrlV(types: [.png]))
        #expect(PasteboardImageDetection.shouldSendCtrlV(types: [.tiff]))
        #expect(PasteboardImageDetection.shouldSendCtrlV(types: [.png, .tiff]))
        #expect(PasteboardImageDetection.shouldSendCtrlV(types: [.init("public.jpeg")]))
        #expect(PasteboardImageDetection.shouldSendCtrlV(types: [.init("public.heic")]))
    }

    @Test func imageWithTextPastesNormally() {
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.png, .string]))
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.string, .tiff]))
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.png, .init("public.utf8-plain-text")]))
    }

    @Test func copiedImageFilePastesItsPath() {
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.fileURL, .png]))
    }

    @Test func textOnlyPastesNormally() {
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.string]))
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.rtf, .string]))
    }

    @Test func emptyOrUnrelatedTypesPasteNormally() {
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: []))
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.html]))
        #expect(!PasteboardImageDetection.shouldSendCtrlV(types: [.init("com.example.opaque")]))
    }

    @Test func pasteActionFollowsConfigAndPasteboardContent() {
        let cases: [(Bool, [NSPasteboard.PasteboardType], PasteboardImageDetection.PasteAction)] = [
            (true, [.png], .sendCtrlV),
            (true, [.tiff], .sendCtrlV),
            (true, [.png, .string], .pasteFromClipboard),
            (true, [.fileURL, .png], .pasteFromClipboard),
            (true, [.string], .pasteFromClipboard),
            (true, [], .pasteFromClipboard),
            (false, [.png], .pasteFromClipboard),
            (false, [.string], .pasteFromClipboard),
        ]
        for (enabled, types, expected) in cases {
            #expect(PasteboardImageDetection.pasteAction(sendsCtrlVForImages: enabled, types: types) == expected)
        }
    }

    @Test func actionIsTheTextKeybindForCtrlV() {
        #expect(PasteboardImageDetection.ctrlVAction == "text:\\x16")
    }
}
