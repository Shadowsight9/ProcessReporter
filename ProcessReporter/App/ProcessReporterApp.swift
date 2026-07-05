import AppKit
import SwiftUI

var reporter: Reporter?

@main
struct ProcessReporterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var statusStore = StatusMenuStore.shared

    init() {
        Task { @MainActor in
            do {
                try await DataStore.shared.initialize()
                reporter = Reporter()
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Database Initialization Failed"
                alert.informativeText = error.localizedDescription
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("ProcessReporter", systemImage: statusStore.systemImage) {
            StatusMenuView()
        }
        Settings {
            SettingsRootView()
        }
        .commands {
            CommandMenu("Edit") {
                Button("Undo") {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                }
                .keyboardShortcut("z")

                Button("Redo") {
                    NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                }
                .keyboardShortcut("Z")

                Divider()

                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x")

                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c")

                Button("Paste") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v")

                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a")
            }
        }
    }
}

func setupMenu() {
    let mainMenu = NSMenu()

    mainMenu.addItem(makeAppMenu())
    mainMenu.addItem(makeEditMenu())

    // 设置主菜单
    NSApp.mainMenu = mainMenu
}

private func makeAppMenu() -> NSMenuItem {
    let appName = ProcessInfo.processInfo.processName
    let appMenu = NSMenu(title: appName)
    let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
    appMenuItem.submenu = appMenu

    appMenu.addItem(NSMenuItem(
        title: "Quit \(appName)",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    ))
    
    appMenu.addItem(NSMenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "w"
    ))

    return appMenuItem
}



private func makeEditMenu() -> NSMenuItem {
    let editMenu = NSMenu(title: "Edit")
    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editMenuItem.submenu = editMenu

    enum MenuEntry {
        case item(title: String, action: Selector, keyEquivalent: String)
        case separator
    }

    let editingItems: [MenuEntry] = [
        .item(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
        .item(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
        .item(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
        .item(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        .separator,
        .item(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
        .item(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
    ]

    editingItems.forEach { item in
        switch item {
        case let .item(title, action, keyEquivalent):
            editMenu.addItem(NSMenuItem(
                title: title,
                action: action,
                keyEquivalent: keyEquivalent
            ))
        case .separator:
            editMenu.addItem(.separator())
        }
    }

    return editMenuItem
}
