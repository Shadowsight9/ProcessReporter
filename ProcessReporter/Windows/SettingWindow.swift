//
//  SettingWindow.swift
//  ProcessReporter
//
//  Created by Innei on 2025/4/6.
//

import AppKit
import SnapKit
import SwiftUI

class SettingWindow: NSWindow {
	private let rootViewController = NSHostingController(rootView: SettingsRootView())

	private let defaultFrameSize = NSSize(width: 760, height: 520)

	// UserDefaults keys for window position and size
	private let windowFrameKey = "SettingWindowFrame"

	convenience init() {
		self.init(
			contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable, .resizable],
			backing: .buffered, defer: false)
		contentViewController = rootViewController

		rootViewController.view.frame.size = defaultFrameSize
		self.isReleasedWhenClosed = false
		title = "Settings"

		positionWindow()

		delegate = self
	}

	private func positionWindow() {
//        // Try to restore saved position and size
//        if let savedFrameData = UserDefaults.standard.data(forKey: windowFrameKey),
//           let nsValue = try? NSKeyedUnarchiver.unarchivedObject(
//               ofClass: NSValue.self, from: savedFrameData),
//           let savedFrame = nsValue.rectValue as NSRect?
//        {
//            // Check if the saved frame is visible on any current screen
//            var isOnScreen = false
//            for screen in NSScreen.screens {
//                if screen.frame.intersects(savedFrame) {
//                    isOnScreen = true
//                    break
//                }
//            }
//
//            if isOnScreen {
//                setFrame(savedFrame, display: true)
//            } else {
//                // Fallback to default center position
//                setFrame(.init(origin: .zero, size: defaultFrameSize), display: true)
//                centerWindowOnScreen()
//            }
//        } else {
//            // No saved data, use default
//            setFrame(.init(origin: .zero, size: defaultFrameSize), display: true)
//            centerWindowOnScreen()
//        }
#if DEBUG
		let visibleFrame = NSScreen.main!.visibleFrame
		setFrame(.init(origin: .init(x: visibleFrame.minX + 20, y: visibleFrame.height / 2 - 500), size: defaultFrameSize), display: true)
#else
		setFrame(.init(origin: .zero, size: defaultFrameSize), display: true)
		centerWindowOnScreen()
#endif
	}

	private func centerWindowOnScreen() {
		if let screen = NSScreen.main {
			let screenFrame = screen.frame
			let windowFrame = frame
			let x = screenFrame.midX - windowFrame.width / 2
			let y = screenFrame.midY - windowFrame.height / 2
			setFrameOrigin(NSPoint(x: x, y: y))
		}
	}

	//    private func saveWindowFrame() {
	//        let nsValue = NSValue(rect: frame)
	//        let frameData = try? NSKeyedArchiver.archivedData(
	//            withRootObject: nsValue, requiringSecureCoding: true)
	//        UserDefaults.standard.set(frameData, forKey: windowFrameKey)
	//    }

}

// MARK: - Window Delegate

extension SettingWindow: NSWindowDelegate {
	func windowShouldClose(_ sender: NSWindow) -> Bool {
		SettingWindowManager.shared.closeWindow()
		return false
	}

	func windowWillClose(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)
	}

	func windowDidBecomeKey(_ notification: Notification) {
		NSApp.setActivationPolicy(.regular)
		NSApplication.shared.activate()
	}

	func windowDidResignKey(_ notification: Notification) {
		let sender = notification.object as! NSWindow
		if !sender.isVisible {
			NSApp.setActivationPolicy(.accessory)
		}
	}

	// Save window position and size when window is moved or resized
	//    func windowDidResize(_ notification: Notification) {
	//        saveWindowFrame()
	//    }
//
	//    func windowDidMove(_ notification: Notification) {
	//        saveWindowFrame()
	//    }
}
