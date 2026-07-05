import AppKit

var reporter: Reporter?

func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    Task { @MainActor in
        do {
            try await DataStore.shared.initialize()
            reporter = Reporter()
        } catch {
            NSLog("Failed to initialize database: \(error)")
            // Show alert to user
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Database Initialization Failed"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    setupMenu()
    _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
}

private func setupMenu() {
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

main()
