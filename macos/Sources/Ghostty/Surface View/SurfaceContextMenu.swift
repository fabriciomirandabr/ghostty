import AppKit
import SwiftUI

enum SurfaceContextMenu {
    struct Context: Equatable {
        var hasSelection: Bool
        var isReadonly: Bool
        var isWorkspaceWindow: Bool
    }

    enum Entry: Equatable {
        case item(Item)
        case separator
    }

    struct Item: Equatable {
        let title: String
        let selector: Selector
        let bindingAction: String?
        let symbol: String?
        let isEnabled: Bool
        let state: NSControl.StateValue
        let shortcut: KeyboardShortcut?
    }

    enum Action {
        static let newTab = "new_tab"
        static let copyAsHTML = "copy_to_clipboard:html"
        static let clearScreen = "clear_screen"
        static let renameTab = "prompt_tab_title"
    }

    static let dispatchedActions: [Selector: String] = [
        #selector(Ghostty.SurfaceView.newTerminalFromContextMenu(_:)): Action.newTab,
        #selector(Ghostty.SurfaceView.copyAsHTMLFromContextMenu(_:)): Action.copyAsHTML,
        #selector(Ghostty.SurfaceView.clearScreenFromContextMenu(_:)): Action.clearScreen,
        #selector(Ghostty.SurfaceView.renameTerminalFromContextMenu(_:)): Action.renameTab,
    ]

    static func entries(
        context: Context,
        shortcut: (String) -> KeyboardShortcut?
    ) -> [Entry] {
        func item(
            _ title: String,
            _ selector: Selector,
            _ bindingAction: String?,
            symbol: String? = nil,
            isEnabled: Bool = true,
            state: NSControl.StateValue = .off
        ) -> Entry {
            .item(Item(
                title: title,
                selector: selector,
                bindingAction: bindingAction,
                symbol: symbol,
                isEnabled: isEnabled,
                state: state,
                shortcut: bindingAction.flatMap(shortcut)))
        }

        let splitRight = item(
            "Split Right",
            #selector(Ghostty.SurfaceView.splitRight(_:)),
            "new_split:right",
            symbol: "rectangle.righthalf.inset.filled")
        let splitLeft = item(
            "Split Left",
            #selector(Ghostty.SurfaceView.splitLeft(_:)),
            "new_split:left",
            symbol: "rectangle.leadinghalf.inset.filled")
        let splitDown = item(
            "Split Down",
            #selector(Ghostty.SurfaceView.splitDown(_:)),
            "new_split:down",
            symbol: "rectangle.bottomhalf.inset.filled")
        let splitUp = item(
            "Split Up",
            #selector(Ghostty.SurfaceView.splitUp(_:)),
            "new_split:up",
            symbol: "rectangle.tophalf.inset.filled")
        let reset = item(
            "Reset Terminal",
            #selector(Ghostty.SurfaceView.resetTerminal(_:)),
            "reset",
            symbol: "arrow.trianglehead.2.clockwise")
        let inspector = item(
            "Toggle Terminal Inspector",
            #selector(Ghostty.SurfaceView.toggleTerminalInspector(_:)),
            "inspector:toggle",
            symbol: "scope")
        let readonly = item(
            "Terminal Read-only",
            #selector(Ghostty.SurfaceView.toggleReadonly(_:)),
            "toggle_readonly",
            symbol: "eye.fill",
            state: context.isReadonly ? .on : .off)
        func paste(_ symbol: String?) -> Entry {
            item(
                "Paste",
                #selector(Ghostty.SurfaceView.paste(_:)),
                "paste_from_clipboard",
                symbol: symbol)
        }

        guard context.isWorkspaceWindow else {
            var stock: [Entry] = []
            if context.hasSelection {
                stock.append(item(
                    "Copy",
                    #selector(Ghostty.SurfaceView.copy(_:)),
                    "copy_to_clipboard"))
            }
            stock.append(paste(nil))
            stock.append(.separator)
            stock.append(contentsOf: [splitRight, splitLeft, splitDown, splitUp])
            stock.append(.separator)
            stock.append(item(
                "Close Split",
                #selector(Ghostty.SurfaceView.closeSurface(_:)),
                "close_surface",
                symbol: "xmark.rectangle"))
            stock.append(.separator)
            stock.append(contentsOf: [reset, inspector, readonly])
            stock.append(.separator)
            stock.append(item(
                "Change Tab Title...",
                #selector(BaseTerminalController.changeTabTitle(_:)),
                "prompt_tab_title",
                symbol: "pencil.line"))
            stock.append(item(
                "Change Terminal Title...",
                #selector(Ghostty.SurfaceView.changeTitle(_:)),
                "prompt_surface_title"))
            return stock
        }

        return [
            item(
                String(localized: "New Terminal"),
                #selector(Ghostty.SurfaceView.newTerminalFromContextMenu(_:)),
                Action.newTab,
                symbol: "plus"),
            item(
                String(localized: "Split Terminal"),
                #selector(Ghostty.SurfaceView.splitRight(_:)),
                "new_split:right",
                symbol: "rectangle.righthalf.inset.filled"),
            splitDown,
            splitLeft,
            splitUp,
            .separator,
            item(
                "Copy",
                #selector(Ghostty.SurfaceView.copy(_:)),
                "copy_to_clipboard",
                symbol: "doc.on.doc",
                isEnabled: context.hasSelection),
            item(
                String(localized: "Copy as HTML"),
                #selector(Ghostty.SurfaceView.copyAsHTMLFromContextMenu(_:)),
                Action.copyAsHTML,
                symbol: "chevron.left.forwardslash.chevron.right",
                isEnabled: context.hasSelection),
            paste("doc.on.clipboard"),
            item(
                String(localized: "Select All"),
                #selector(Ghostty.SurfaceView.selectAll(_:)),
                "select_all",
                symbol: "selection.pin.in.out"),
            .separator,
            item(
                String(localized: "Clear"),
                #selector(Ghostty.SurfaceView.clearScreenFromContextMenu(_:)),
                Action.clearScreen,
                symbol: "eraser"),
            item(
                String(localized: "Kill Terminal"),
                #selector(Ghostty.SurfaceView.closeSurface(_:)),
                "close_surface",
                symbol: "xmark.rectangle"),
            .separator,
            reset,
            inspector,
            readonly,
            .separator,
            item(
                String(localized: "Rename Terminal…"),
                #selector(Ghostty.SurfaceView.renameTerminalFromContextMenu(_:)),
                Action.renameTab,
                symbol: "pencil.line"),
            item(
                "Change Terminal Title…",
                #selector(Ghostty.SurfaceView.changeTitle(_:)),
                "prompt_surface_title"),
        ]
    }

    @MainActor
    static func menu(from entries: [Entry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())

            case .item(let item):
                let menuItem = menu.addItem(
                    withTitle: item.title,
                    action: item.selector,
                    keyEquivalent: "")
                if let symbol = item.symbol {
                    menuItem.setImageIfDesired(systemSymbolName: symbol)
                }
                menuItem.isEnabled = item.isEnabled
                menuItem.state = item.state
                if let shortcut = item.shortcut {
                    menuItem.keyEquivalent = shortcut.key.character.description
                    menuItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(swiftUIFlags: shortcut.modifiers)
                }
            }
        }

        return menu
    }
}
