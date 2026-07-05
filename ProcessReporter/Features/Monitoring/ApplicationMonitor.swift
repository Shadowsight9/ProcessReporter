//
//  ApplicationMonitor.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/7.
//

import Accessibility
import AppKit
import Foundation

class ApplicationMonitor {
    static let shared = ApplicationMonitor()

    private var mouseEventMonitor: Any?
    private var windowFocusObserver: Any?
    private var didRequestAccessibilityPrompt = false
    private var lastAccessibilityToastDate = Date.distantPast

    private let accessibilityToastCooldown: TimeInterval = 60

    // Mouse event callback
    var onMouseClicked: ((MouseClickInfo) -> Void)?
    // Window focus change callback
    var onWindowFocusChanged: ((FocusedWindowInfo) -> Void)?

    private init() {}

    @discardableResult
    private func checkAndRequestAccessibilityPermissions(promptIfNeeded: Bool = true) -> Bool {
        if isAccessibilityEnabled() {
            return true
        }

        guard promptIfNeeded else {
            return AXIsProcessTrusted()
        }

        if didRequestAccessibilityPrompt {
            return AXIsProcessTrusted()
        }

        didRequestAccessibilityPrompt = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibilityAuthorization() -> Bool {
        if isAccessibilityEnabled() {
            return true
        }

        didRequestAccessibilityPrompt = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !accessibilityEnabled {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        return accessibilityEnabled
    }

    private func getWindowTitle(_ pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)

        var mainWindowValue: CFTypeRef?
        let mainWindowResult = AXUIElementCopyAttributeValue(
            app,
            kAXMainWindowAttribute as CFString,
            &mainWindowValue
        )

        guard mainWindowResult == .success else {
            return nil
        }

        guard let mainWindow = mainWindowValue as! AXUIElement? else {
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            mainWindow,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success else {
            return nil
        }

        guard let title = titleValue as? String else {
            return nil
        }

        return title
    }

    func getFocusedWindowInfo() -> FocusedWindowInfo? {
        guard isAccessibilityEnabled() else {
            showAccessibilityToastIfNeeded()
            return nil
        }

        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let applicationIdentifier = app.bundleIdentifier ?? ""

        if IgnoreSystemApplication.contains(applicationIdentifier) {
            return nil
        }

        let appName = app.localizedName ?? "Unknown"
        let icon = app.icon
        let title = getWindowTitle(app.processIdentifier)

        return FocusedWindowInfo(
            appName: appName, icon: icon,
            applicationIdentifier: applicationIdentifier,
            title: title
        )
    }

    func startMouseMonitoring(promptIfNeeded: Bool = true) {
        guard checkAndRequestAccessibilityPermissions(promptIfNeeded: promptIfNeeded) else {
            return
        }

        // Stop existing monitor if any
        stopMouseMonitoring()

        // Create new monitor for mouse down events
        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [
            .leftMouseDown, .rightMouseDown,
        ]) { [weak self] event in
            let clickInfo = MouseClickInfo(
                location: event.locationInWindow,
                timestamp: event.timestamp
            )
            self?.onMouseClicked?(clickInfo)
        }
    }

    func stopMouseMonitoring() {
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
    }

    func startWindowFocusMonitoring(promptIfNeeded: Bool = true) {
        guard checkAndRequestAccessibilityPermissions(promptIfNeeded: promptIfNeeded) else {
            return
        }

        // Stop existing observer if any
        stopWindowFocusMonitoring()

        // Start observing active application changes
        windowFocusObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self,
                let windowInfo = self.getFocusedWindowInfo()
            else {
                return
            }
            self.onWindowFocusChanged?(windowInfo)
        }
    }

    func stopWindowFocusMonitoring() {
        if let observer = windowFocusObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            windowFocusObserver = nil
        }
    }

    private func showAccessibilityToastIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastAccessibilityToastDate) >= accessibilityToastCooldown else {
            return
        }

        lastAccessibilityToastDate = now
        ToastManager.shared.error("Accessibility permissions are required to monitor window changes.")
    }

    deinit {
        stopMouseMonitoring()
        stopWindowFocusMonitoring()
    }
}
