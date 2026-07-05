import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowPresenter()

    private var window: NSWindow?
    private let size = NSSize(width: 760, height: 520)

    func showWindow() {
        setupMenu()

        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            let controller = NSHostingController(rootView: SettingsRootView())
            let newWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.contentViewController = controller
            newWindow.isReleasedWhenClosed = false
            newWindow.title = "Settings"
            newWindow.center()
            newWindow.delegate = self
            window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        window?.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        AppUtility.shared.clearCache()
        window = nil
        return true
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenu()
        NSApplication.shared.activate()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let sender = notification.object as? NSWindow, !sender.isVisible else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
